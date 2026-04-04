//
// CodecService.swift
// J2KSwift
//
// Bridges J2KCodec into J2KTestApp view models by providing real
// encode/decode functions. This file lives in the J2KTestApp target
// so it can import both J2KCore and J2KCodec without creating a
// circular dependency.
//

#if canImport(SwiftUI) && os(macOS)
import Foundation
import J2KCore
import J2KCodec

// MARK: - Codec Service

/// Provides real JPEG 2000 encoding and decoding functions that can be
/// injected into the view models defined in J2KCore.
enum CodecService {

    // MARK: - Encoder

    /// Returns a closure suitable for ``EncodeViewModel/encoderFunction``.
    ///
    /// The closure takes raw planar pixel data (R...G...B...), image
    /// dimensions, component count, and UI configuration, then returns
    /// the encoded JPEG 2000 codestream.
    static var encoderFunction: @Sendable (Data, Int, Int, Int, EncodeConfiguration) throws -> Data {
        { pixelData, width, height, componentCount, uiConfig in
            let encodingConfig = Self.makeEncodingConfiguration(from: uiConfig)
            let image = Self.makeJ2KImage(
                pixelData: pixelData,
                width: width,
                height: height,
                componentCount: componentCount,
                tileWidth: uiConfig.tileWidth,
                tileHeight: uiConfig.tileHeight
            )
            let encoder = J2KEncoder(encodingConfiguration: encodingConfig)
            return try encoder.encode(image)
        }
    }

    // MARK: - Decoder

    /// Returns a closure suitable for ``DecodeViewModel/decoderFunction``
    /// and ``RoundTripViewModel/decoderFunction``.
    ///
    /// The closure takes a JPEG 2000 codestream and returns
    /// `(planarPixelData, width, height, componentCount)`.
    static var decoderFunction: @Sendable (Data) throws -> (Data, Int, Int, Int) {
        { codestreamData in
            let decoder = J2KDecoder()
            let image = try decoder.decode(codestreamData)

            let width = image.width
            let height = image.height
            let componentCount = image.componentCount
            let pixelCount = width * height

            // Build planar pixel data from J2KImage components
            var pixelData = Data(count: pixelCount * componentCount)
            pixelData.withUnsafeMutableBytes { outBuf in
                let out = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                for c in 0..<min(componentCount, image.components.count) {
                    let comp = image.components[c]
                    comp.data.withUnsafeBytes { compBuf in
                        let inp = compBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let count = min(pixelCount, comp.data.count)
                        for i in 0..<count {
                            out[c * pixelCount + i] = inp[i]
                        }
                    }
                }
            }

            return (pixelData, width, height, componentCount)
        }
    }

    // MARK: - Configuration Mapping

    /// Maps the UI ``EncodeConfiguration`` to the codec's ``J2KEncodingConfiguration``.
    private static func makeEncodingConfiguration(from ui: EncodeConfiguration) -> J2KEncodingConfiguration {
        let isLossless = ui.waveletType == .fiveThree && ui.quality >= 1.0
        let progressionOrder: J2KProgressionOrder = {
            switch ui.progressionOrder {
            case .lrcp: return .lrcp
            case .rlcp: return .rlcp
            case .rpcl: return .rpcl
            case .pcrl: return .pcrl
            case .cprl: return .cprl
            }
        }()

        return J2KEncodingConfiguration(
            quality: ui.quality,
            lossless: isLossless,
            decompositionLevels: ui.decompositionLevels,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: ui.qualityLayers,
            progressionOrder: progressionOrder,
            tileSize: (width: ui.tileWidth, height: ui.tileHeight),
            useHTJ2K: ui.htj2kEnabled
        )
    }

    // MARK: - Image Construction

    /// Builds a ``J2KImage`` from planar pixel data.
    ///
    /// - Parameters:
    ///   - pixelData: Raw planar data (R plane | G plane | B plane).
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - componentCount: Number of colour components (1 or 3).
    ///   - tileWidth: Tile width (0 = untiled).
    ///   - tileHeight: Tile height (0 = untiled).
    /// - Returns: A validated ``J2KImage``.
    private static func makeJ2KImage(
        pixelData: Data,
        width: Int,
        height: Int,
        componentCount: Int,
        tileWidth: Int = 0,
        tileHeight: Int = 0
    ) -> J2KImage {
        let pixelCount = width * height
        var components: [J2KComponent] = []
        for c in 0..<componentCount {
            let start = c * pixelCount
            let end = min(start + pixelCount, pixelData.count)
            let componentData = pixelData.subdata(in: start..<end)
            components.append(J2KComponent(
                index: c,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                data: componentData
            ))
        }
        return J2KImage(
            width: width,
            height: height,
            components: components,
            tileWidth: tileWidth,
            tileHeight: tileHeight
        )
    }

    // MARK: - View Model Wiring

    /// Injects real codec functions into all view models.
    @MainActor
    static func wireViewModels(
        encode: EncodeViewModel,
        decode: DecodeViewModel,
        roundTrip: RoundTripViewModel
    ) {
        encode.encoderFunction = encoderFunction
        encode.decoderFunction = decoderFunction
        decode.decoderFunction = decoderFunction
        roundTrip.decoderFunction = decoderFunction
        roundTrip.encodeViewModel.encoderFunction = encoderFunction
    }
}
#endif
