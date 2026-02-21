// J2KXSEncoder.swift
// J2KSwift
//
// JPEG XS encoder (ISO/IEC 21122).
//
// The encoder divides each image component into horizontal slices, applies
// the slice DWT, quantises the subbands, entropy-codes the results, and
// serialises the codestream using the JPEG XS packetiser.

import Foundation
import J2KCore

// MARK: - J2KXSEncoder

/// JPEG XS image encoder.
///
/// Encodes a ``J2KXSImage`` into a JPEG XS codestream according to the
/// parameters in a ``J2KXSConfiguration``.  The encode pipeline is:
/// 1. Validate dimensions and plane count.
/// 2. Divide each component into slices of the configured height.
/// 3. Apply the slice-based DWT (``J2KXSDWTEngine``).
/// 4. Quantise each subband (``J2KXSQuantiser``).
/// 5. Entropy-code and packetise slices (``J2KXSPacketiser``).
/// 6. Assemble the full codestream.
///
/// Example:
/// ```swift
/// let encoder = J2KXSEncoder()
/// let result = try await encoder.encode(image, configuration: .preview)
/// ```
public actor J2KXSEncoder {
    private let dwtEngine = J2KXSDWTEngine()
    private let quantiser = J2KXSQuantiser()
    private let packetiser = J2KXSPacketiser()

    /// Total images encoded since creation.
    private(set) var encodedImageCount: Int = 0

    /// Creates a new JPEG XS encoder.
    public init() {}

    // MARK: Encode

    /// Encodes a ``J2KXSImage`` using the supplied configuration.
    ///
    /// - Parameters:
    ///   - image: The source image to encode.
    ///   - configuration: Encoding parameters (profile, level, slice height,
    ///     target bit-rate).
    /// - Returns: A ``J2KXSEncodeResult`` containing the codestream and
    ///            encode metadata.
    /// - Throws: ``J2KXSError/unsupportedProfile(_:)`` if the image component
    ///           count exceeds the profile's `maxComponents`.
    ///           ``J2KXSError/planeMismatch(expected:got:)`` if the plane count
    ///           is incorrect.
    ///           ``J2KXSError/invalidConfiguration(_:)`` for invalid dimensions.
    public func encode(
        _ image: J2KXSImage,
        configuration: J2KXSConfiguration = .preview
    ) async throws -> J2KXSEncodeResult {
        // Validate component count against profile.
        let componentCount = image.planes.count
        guard componentCount <= configuration.profile.maxComponents else {
            throw J2KXSError.unsupportedProfile(configuration.profile)
        }

        // Validate plane count matches pixel format.
        let expectedPlanes = image.pixelFormat.planeCount
        guard componentCount == expectedPlanes else {
            throw J2KXSError.planeMismatch(expected: expectedPlanes, got: componentCount)
        }

        guard image.width > 0, image.height > 0 else {
            throw J2KXSError.invalidConfiguration(
                "Image dimensions must be positive (got \(image.width)×\(image.height))."
            )
        }

        let startTime = Date()

        // Determine DWT decomposition levels and quantisation step from bpp.
        let decompositionLevels = decompositionLevelsForConfiguration(configuration)
        let stepSize = stepSizeForBitsPerPixel(configuration.targetBitsPerPixel)
        let quantisationParams = J2KXSQuantisationParameters(stepSize: stepSize, deadZoneOffset: 0.1)
        let sliceHeight = configuration.sliceHeight.pixels

        var allSlices: [J2KXSEncodedSlice] = []

        for (componentIdx, plane) in image.planes.enumerated() {
            let samples = floatSamples(from: plane, count: image.width * image.height)
            let componentSlices = try await encodeComponent(
                samples: samples,
                width: image.width,
                height: image.height,
                componentIndex: componentIdx,
                sliceHeight: sliceHeight,
                decompositionLevels: decompositionLevels,
                quantisationParams: quantisationParams
            )
            allSlices.append(contentsOf: componentSlices)
        }

        let codestream = try await packetiser.pack(slices: allSlices, mode: .significanceRange)

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        encodedImageCount += 1

        return J2KXSEncodeResult(
            encodedData: codestream,
            profile: configuration.profile,
            level: configuration.level,
            sliceCount: allSlices.count,
            encodingTimeMs: elapsed
        )
    }

    // MARK: - Private Helpers

    /// Encodes all slices of one image component.
    private func encodeComponent(
        samples: [Float],
        width: Int,
        height: Int,
        componentIndex: Int,
        sliceHeight: Int,
        decompositionLevels: Int,
        quantisationParams: J2KXSQuantisationParameters
    ) async throws -> [J2KXSEncodedSlice] {
        var slices: [J2KXSEncodedSlice] = []
        var lineOffset = 0

        while lineOffset < height {
            let currentHeight = min(sliceHeight, height - lineOffset)
            let startSample = lineOffset * width
            let endSample = startSample + currentHeight * width
            let sliceSamples = Array(samples[startSample..<endSample])

            // DWT — reduce levels if slice is too small.
            let maxLevels = maxDecompositionLevels(width: width, height: currentHeight)
            let effectiveLevels = min(decompositionLevels, maxLevels)

            let decomp = try await dwtEngine.forward(
                slice: sliceSamples,
                width: width,
                height: currentHeight,
                levels: effectiveLevels
            )

            // Quantise and encode each subband.
            var payload = Data()
            for subband in decomp.subbands {
                let qCoeffs = await quantiser.quantise(subband: subband, parameters: quantisationParams)
                payload.append(serialiseQuantised(qCoeffs))
            }

            slices.append(J2KXSEncodedSlice(
                data: payload,
                lineOffset: lineOffset,
                lineCount: currentHeight,
                componentIndex: componentIndex
            ))
            lineOffset += currentHeight
        }

        return slices
    }

    /// Converts a `Data` plane to normalised `[Float]` samples.
    private func floatSamples(from plane: Data, count: Int) -> [Float] {
        guard !plane.isEmpty else { return [Float](repeating: 0, count: count) }
        let bytes = [UInt8](plane)
        return bytes.prefix(count).map { Float($0) / 255.0 }
    }

    /// Serialises quantised coefficients to bytes (simple run of Int16 values).
    private func serialiseQuantised(_ q: J2KXSQuantisedCoefficients) -> Data {
        var data = Data(capacity: q.values.count * 2 + 4)
        // Subband header: orientation (1 byte), level (1 byte), step index (1 byte), count (varint 4 bytes)
        data.append(UInt8(q.orientation == .ll ? 0 : q.orientation == .lh ? 1 : q.orientation == .hl ? 2 : 3))
        data.append(UInt8(q.level & 0xFF))
        data.append(UInt8(q.stepIndex & 0xFF))
        data.append(UInt8((q.values.count >> 8) & 0xFF))
        data.append(UInt8(q.values.count & 0xFF))
        for v in q.values {
            let clamped = Int16(exactly: max(Int32(Int16.min), min(Int32(Int16.max), v))) ?? 0
            data.append(UInt8(bitPattern: Int8(truncatingIfNeeded: clamped >> 8)))
            data.append(UInt8(bitPattern: Int8(truncatingIfNeeded: clamped)))
        }
        return data
    }

    /// Derives a suitable number of DWT decomposition levels from the configuration.
    private func decompositionLevelsForConfiguration(_ config: J2KXSConfiguration) -> Int {
        // Higher quality → more decomposition levels (up to 2).
        config.targetBitsPerPixel >= 4.0 ? 2 : 1
    }

    /// Derives a quantisation step size from the target bits-per-pixel.
    private func stepSizeForBitsPerPixel(_ bpp: Double) -> Float {
        // Rough inverse relationship: lower bpp → larger step.
        Float(max(0.5, 16.0 / bpp))
    }

    /// The maximum safe decomposition levels for a given slice size.
    private func maxDecompositionLevels(width: Int, height: Int) -> Int {
        var levels = 0
        var currentWidth = width
        var currentHeight = height
        while currentWidth >= 2, currentHeight >= 2 {
            currentWidth /= 2
            currentHeight /= 2
            levels += 1
        }
        return max(1, levels)
    }
}
