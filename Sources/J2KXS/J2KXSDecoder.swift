// J2KXSDecoder.swift
// J2KSwift
//
// JPEG XS decoder (ISO/IEC 21122).
//
// The decoder unpacks the codestream into slices, dequantises the
// coefficients, applies the inverse slice DWT, and reassembles the
// reconstructed image planes.

import Foundation
import J2KCore

// MARK: - J2KXSDecoder

/// JPEG XS image decoder.
///
/// Decodes a JPEG XS codestream produced by ``J2KXSEncoder`` into a
/// ``J2KXSDecodeResult``.  The decode pipeline mirrors the encoder in
/// reverse:
/// 1. Unpack slices from the codestream (``J2KXSPacketiser``).
/// 2. Dequantise subband coefficients (``J2KXSQuantiser``).
/// 3. Apply the inverse slice DWT (``J2KXSDWTEngine``).
/// 4. Reassemble component planes.
/// 5. Construct the output ``J2KXSImage``.
///
/// Example:
/// ```swift
/// let decoder = J2KXSDecoder()
/// let result = try await decoder.decode(encodeResult)
/// ```
public actor J2KXSDecoder {
    private let dwtEngine = J2KXSDWTEngine()
    private let quantiser = J2KXSQuantiser()
    private let packetiser = J2KXSPacketiser()

    /// Total images decoded since creation.
    private(set) var decodedImageCount: Int = 0

    /// Creates a new JPEG XS decoder.
    public init() {}

    // MARK: Decode

    /// Decodes a ``J2KXSEncodeResult`` into a ``J2KXSDecodeResult``.
    ///
    /// This convenience overload reads the profile and level from the
    /// encode result rather than re-parsing them from the raw codestream.
    ///
    /// - Parameter encodeResult: A result produced by ``J2KXSEncoder``.
    /// - Returns: A ``J2KXSDecodeResult`` with the reconstructed image.
    /// - Throws: ``J2KXSError/decodingFailed(_:)`` if the codestream is
    ///           invalid or inconsistent.
    public func decode(
        _ encodeResult: J2KXSEncodeResult,
        pixelFormat: J2KXSPixelFormat = .rgb,
        width: Int,
        height: Int
    ) async throws -> J2KXSDecodeResult {
        let startTime = Date()

        let slices = try await packetiser.unpack(encodeResult.encodedData)
        guard !slices.isEmpty else {
            throw J2KXSError.decodingFailed("Codestream contains no slices.")
        }

        // Group slices by component index.
        var componentSlices: [Int: [J2KXSEncodedSlice]] = [:]
        for slice in slices {
            componentSlices[slice.componentIndex, default: []].append(slice)
        }

        // Sort component slices by line offset.
        for key in componentSlices.keys {
            componentSlices[key]?.sort { $0.lineOffset < $1.lineOffset }
        }

        var planes: [Data] = []
        let componentCount = pixelFormat.planeCount
        for componentIdx in 0..<componentCount {
            let compSlices = componentSlices[componentIdx] ?? []
            let plane = try await reconstructPlane(
                from: compSlices,
                width: width,
                height: height
            )
            planes.append(plane)
        }

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        decodedImageCount += 1

        let image = J2KXSImage(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            planes: planes
        )
        return J2KXSDecodeResult(
            image: image,
            profile: encodeResult.profile,
            level: encodeResult.level,
            decodingTimeMs: elapsed
        )
    }

    // MARK: - Private Helpers

    /// Reconstructs one component plane from its encoded slices.
    private func reconstructPlane(
        from slices: [J2KXSEncodedSlice],
        width: Int,
        height: Int
    ) async throws -> Data {
        var samples = [Float](repeating: 0, count: width * height)

        for slice in slices {
            let sliceHeight = slice.lineCount
            let reconstructed = try await decodeSlice(
                data: slice.data,
                width: width,
                height: sliceHeight
            )

            let startIdx = slice.lineOffset * width
            let endIdx = min(startIdx + reconstructed.count, samples.count)
            if startIdx < endIdx {
                samples.replaceSubrange(startIdx..<endIdx, with: reconstructed.prefix(endIdx - startIdx))
            }
        }

        // Convert normalised [Float] back to UInt8 bytes.
        return Data(samples.map { UInt8(min(255, max(0, Int($0 * 255.0 + 0.5)))) })
    }

    /// Decodes one slice payload into floating-point samples.
    private func decodeSlice(data: Data, width: Int, height: Int) async throws -> [Float] {
        let subbands = try deserialiseQuantised(data: data)
        guard !subbands.isEmpty else {
            // Return zero plane for empty slices.
            return [Float](repeating: 0, count: width * height)
        }

        // Determine decomposition levels from the highest level in the subbands.
        let maxLevel = subbands.max(by: { $0.level < $1.level })?.level ?? 1

        // Dequantise each subband.
        var dequantisedSubbands: [J2KXSSubband] = []
        for subband in subbands {
            let dq = await quantiser.dequantise(subband)
            dequantisedSubbands.append(dq)
        }

        // Reconstruct via inverse DWT.
        let decomp = J2KXSDecompositionResult(
            subbands: dequantisedSubbands,
            decompositionLevels: maxLevel,
            width: width,
            height: height
        )

        return try await dwtEngine.inverse(decomp)
    }

    /// Deserialises a slice payload back into ``J2KXSQuantisedCoefficients``.
    private func deserialiseQuantised(data: Data) throws -> [J2KXSQuantisedCoefficients] {
        let bytes = [UInt8](data)
        var offset = 0
        var result: [J2KXSQuantisedCoefficients] = []

        while offset + 5 <= bytes.count {
            let orientationByte = bytes[offset]
            let level = Int(bytes[offset + 1])
            let stepIndex = Int(bytes[offset + 2])
            let valueCount = Int(bytes[offset + 3]) << 8 | Int(bytes[offset + 4])
            offset += 5

            guard offset + valueCount * 2 <= bytes.count else {
                throw J2KXSError.decodingFailed(
                    "Truncated coefficient data at offset \(offset)."
                )
            }

            let orientation: J2KXSDWTOrientation
            switch orientationByte {
            case 0: orientation = .ll
            case 1: orientation = .lh
            case 2: orientation = .hl
            default: orientation = .hh
            }

            var values = [Int32](repeating: 0, count: valueCount)
            for i in 0..<valueCount {
                let hi = Int16(bitPattern: UInt16(bytes[offset + i * 2]) << 8 | UInt16(bytes[offset + i * 2 + 1]))
                values[i] = Int32(hi)
            }
            offset += valueCount * 2

            // Derive step size from step index (inverse of encoder's log formula).
            let stepSize = Float(pow(2.0, Double(stepIndex) - 128.0))

            // Infer subband dimensions from coefficient count.
            let sqrtCount = Int(ceil(sqrt(Double(valueCount))))
            let sbWidth  = sqrtCount
            let sbHeight = valueCount > 0 ? (valueCount + sqrtCount - 1) / sqrtCount : 1

            result.append(J2KXSQuantisedCoefficients(
                orientation: orientation,
                level: max(1, level),
                values: values,
                stepIndex: stepIndex,
                stepSize: stepSize,
                width: sbWidth,
                height: sbHeight
            ))
        }

        return result
    }
}
