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
import AppKit
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
    static var encoderFunction: @Sendable (Data, Int, Int, Int, EncodeConfiguration, @Sendable (String, Double) -> Void) throws -> Data {
        { pixelData, width, height, componentCount, uiConfig, progressCallback in
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
            // Bridge the @Sendable progress callback into the encoder's
            // synchronous, non-escaping progress closure.
            return try withoutActuallyEscaping({ (update: EncoderProgressUpdate) in
                progressCallback(update.stage.rawValue, update.progress)
            }) { escapableCb in
                try encoder.encode(image, progress: escapableCb)
            }
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
            codeBlockSize: (width: 64, height: 64),
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

    // MARK: - Image Parser

    /// Returns a closure that parses image file data (PNG/TIFF/BMP/DICOM) into
    /// planar pixel data suitable for the encoder.
    ///
    /// Output format: `(planarRGBData, width, height, componentCount)`.
    static var imageParserFunction: @Sendable (Data) throws -> (Data, Int, Int, Int) {
        { fileData in
            // Check for DICOM file (magic "DICM" at offset 128)
            if fileData.count >= 132,
               String(data: fileData.subdata(in: 128..<132), encoding: .ascii) == "DICM" {
                return try Self.parseDICOMPixelData(fileData)
            }

            guard let nsImage = NSImage(data: fileData),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw J2KError.invalidParameter("Could not decode image file")
            }

            let w = cgImage.width
            let h = cgImage.height
            let bytesPerRow = w * 4
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

            guard let context = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: bitmapInfo
            ), let pixelData = context.data else {
                throw J2KError.internalError("Failed to create bitmap context")
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

            let pixelCount = w * h
            let componentCount = 3
            var planar = Data(count: pixelCount * componentCount)
            planar.withUnsafeMutableBytes { outBuf in
                let outPtr = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let inPtr = pixelData.assumingMemoryBound(to: UInt8.self)
                for i in 0..<pixelCount {
                    outPtr[i] = inPtr[i * 4]                        // R
                    outPtr[pixelCount + i] = inPtr[i * 4 + 1]       // G
                    outPtr[pixelCount * 2 + i] = inPtr[i * 4 + 2]   // B
                }
            }
            return (planar, w, h, componentCount)
        }
    }

    // MARK: - Image Renderer

    /// Returns a closure that converts planar pixel data (R plane | G plane | B plane)
    /// to PNG image data suitable for display with `NSImage(data:)`.
    ///
    /// Output: PNG `Data` that `NSImage` and `ImagePreviewView` can render.
    static var imageRendererFunction: @Sendable (Data, Int, Int, Int) -> Data? {
        { planarData, width, height, componentCount in
            let pixelCount = width * height
            let bytesPerRow = width * 4
            var rgba = Data(count: pixelCount * 4)
            rgba.withUnsafeMutableBytes { outBuf in
                let out = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                planarData.withUnsafeBytes { inBuf in
                    let inp = inBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let safePlaneSize = min(pixelCount, planarData.count)
                    if componentCount >= 3 && planarData.count >= pixelCount * 3 {
                        for i in 0..<safePlaneSize {
                            out[i * 4]     = inp[i]                      // R
                            out[i * 4 + 1] = inp[pixelCount + i]         // G
                            out[i * 4 + 2] = inp[pixelCount * 2 + i]     // B
                            out[i * 4 + 3] = 255                         // A
                        }
                    } else {
                        // Grayscale
                        for i in 0..<safePlaneSize {
                            let v = inp[i]
                            out[i * 4]     = v
                            out[i * 4 + 1] = v
                            out[i * 4 + 2] = v
                            out[i * 4 + 3] = 255
                        }
                    }
                }
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            guard let provider = CGDataProvider(data: rgba as CFData),
                  let cgImage = CGImage(
                      width: width, height: height,
                      bitsPerComponent: 8, bitsPerPixel: 32,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                      provider: provider,
                      decode: nil, shouldInterpolate: false,
                      intent: .defaultIntent
                  ) else { return nil }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }
            return pngData
        }
    }

    // MARK: - Codestream Marker Parser

    /// Returns a closure that parses JPEG 2000 codestream markers from raw data.
    ///
    /// Extracts common markers (SOC, SIZ, COD, QCD, SOT, SOD, EOC) with
    /// offset and length information for the marker inspector.
    static var markerParserFunction: @Sendable (Data) -> [CodestreamMarkerInfo] {
        { fileData in
            var markers: [CodestreamMarkerInfo] = []
            let count = fileData.count
            guard count >= 2 else { return markers }

            // Known JPEG 2000 marker codes
            let markerNames: [UInt16: String] = [
                0xFF4F: "SOC", 0xFF51: "SIZ", 0xFF52: "COD", 0xFF53: "COC",
                0xFF5C: "QCD", 0xFF5D: "QCC", 0xFF5E: "RGN", 0xFF55: "TLM",
                0xFF57: "PLM", 0xFF58: "PLT", 0xFF60: "PPM", 0xFF61: "PPT",
                0xFF63: "CRG", 0xFF64: "COM", 0xFF90: "SOT", 0xFF91: "SOP",
                0xFF92: "EPH", 0xFF93: "SOD", 0xFFD9: "EOC", 0xFF50: "CAP",
            ]
            // Markers with no length field
            let noLengthMarkers: Set<UInt16> = [0xFF4F, 0xFF93, 0xFFD9, 0xFF92]

            // Skip JP2 file format box header if present
            var offset = 0
            fileData.withUnsafeBytes { buf in
                let bytes = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)

                // Check for JP2 signature box (0x6A502020)
                if count >= 12 {
                    let sig = (UInt32(bytes[4]) << 24) | (UInt32(bytes[5]) << 16) | (UInt32(bytes[6]) << 8) | UInt32(bytes[7])
                    if sig == 0x6A502020 {
                        // Scan for SOC marker (0xFF4F) within the file
                        for i in 0..<(count - 1) {
                            if bytes[i] == 0xFF && bytes[i + 1] == 0x4F {
                                offset = i
                                break
                            }
                        }
                    }
                }

                while offset < count - 1 {
                    guard bytes[offset] == 0xFF else {
                        offset += 1
                        continue
                    }

                    let markerCode = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])

                    guard let name = markerNames[markerCode] else {
                        offset += 2
                        continue
                    }

                    if noLengthMarkers.contains(markerCode) {
                        var summary = ""
                        switch markerCode {
                        case 0xFF4F: summary = "Start of Codestream"
                        case 0xFF93: summary = "Start of Data"
                        case 0xFFD9: summary = "End of Codestream"
                        case 0xFF92: summary = "End of Packet Header"
                        default: break
                        }
                        markers.append(CodestreamMarkerInfo(name: name, offset: offset, summary: summary))
                        offset += 2
                        if markerCode == 0xFF93 || markerCode == 0xFFD9 {
                            break // SOD/EOC: stop scanning
                        }
                    } else {
                        guard offset + 3 < count else { break }
                        let length = Int(UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3]))

                        var summary = ""
                        if markerCode == 0xFF51 && offset + 9 < count { // SIZ
                            let w = Int(UInt32(bytes[offset + 6]) << 24 | UInt32(bytes[offset + 7]) << 16 | UInt32(bytes[offset + 8]) << 8 | UInt32(bytes[offset + 9]))
                            let h = (offset + 13 < count) ?
                                Int(UInt32(bytes[offset + 10]) << 24 | UInt32(bytes[offset + 11]) << 16 | UInt32(bytes[offset + 12]) << 8 | UInt32(bytes[offset + 13])) : 0
                            let csiz = (offset + Int(length) + 1 < count && length >= 38) ?
                                Int(UInt16(bytes[offset + 40]) << 8 | UInt16(bytes[offset + 41])) : 0
                            summary = "Image size \(w)×\(h), \(csiz) components"
                        } else if markerCode == 0xFF52 { // COD
                            summary = "Coding style default"
                        } else if markerCode == 0xFF5C { // QCD
                            summary = "Quantisation default"
                        } else if markerCode == 0xFF90 && offset + 5 < count { // SOT
                            let tileIndex = Int(UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5]))
                            summary = "Start of Tile \(tileIndex)"
                        } else if markerCode == 0xFF64 { // COM
                            summary = "Comment"
                        } else if markerCode == 0xFF50 { // CAP
                            summary = "Extended capabilities (HTJ2K)"
                        }

                        markers.append(CodestreamMarkerInfo(name: name, offset: offset, length: length, summary: summary))
                        offset += 2 + length
                    }
                }
            }
            return markers
        }
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
        encode.imageParserFunction = imageParserFunction
        encode.imageRendererFunction = imageRendererFunction
        decode.decoderFunction = decoderFunction
        decode.imageRendererFunction = imageRendererFunction
        decode.markerParserFunction = markerParserFunction
        roundTrip.decoderFunction = decoderFunction
        roundTrip.imageRendererFunction = imageRendererFunction
        roundTrip.imageParserFunction = imageParserFunction
        roundTrip.encodeViewModel.encoderFunction = encoderFunction
        roundTrip.encodeViewModel.decoderFunction = decoderFunction
        roundTrip.encodeViewModel.imageParserFunction = imageParserFunction
        roundTrip.encodeViewModel.imageRendererFunction = imageRendererFunction
    }

    // MARK: - DICOM Pixel Data Parser

    /// Parses uncompressed DICOM pixel data and returns planar 8-bit data.
    ///
    /// Supports both explicit and implicit VR, little-endian and big-endian
    /// transfer syntaxes. For 16-bit data, applies a basic window/level
    /// to produce 8-bit output suitable for encoding.
    ///
    /// - Parameter data: Raw DICOM file data (must include 128-byte preamble + "DICM").
    /// - Returns: `(planarPixelData, width, height, componentCount)`.
    /// - Throws: ``J2KError`` if the file is invalid or uses an unsupported transfer syntax.
    private static func parseDICOMPixelData(_ data: Data) throws -> (Data, Int, Int, Int) {
        guard data.count >= 136 else {
            throw J2KError.invalidParameter("Not a valid DICOM file: too small")
        }

        var offset = 132
        var isExplicitVR = true
        var isBigEndian = false

        // Parse Group 0002 (File Meta Information, always Explicit VR LE)
        while offset + 8 <= data.count {
            let group = readU16LE(data, offset)
            if group != 0x0002 { break }

            let element = readU16LE(data, offset + 2)
            let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)), encoding: .ascii) ?? ""
            let (valLen, hdrSize) = dicomValueLength(data, offset: offset, vr: vr, bigEndian: false)
            let valStart = offset + hdrSize

            if element == 0x0010, let tsUID = dicomReadString(data, valStart, valLen) {
                let ts = tsUID.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(["\0"])))
                switch ts {
                case "1.2.840.10008.1.2":
                    isExplicitVR = false; isBigEndian = false
                case "1.2.840.10008.1.2.1":
                    isExplicitVR = true; isBigEndian = false
                case "1.2.840.10008.1.2.2":
                    isExplicitVR = true; isBigEndian = true
                default:
                    if ts.hasPrefix("1.2.840.10008.1.2.4") || ts.hasPrefix("1.2.840.10008.1.2.5") {
                        throw J2KError.invalidParameter("Compressed DICOM not supported. Only uncompressed DICOM files can be loaded.")
                    }
                }
            }
            offset = valStart + valLen
        }

        // Parse dataset tags
        var rows = 0, columns = 0, bitsAllocated = 16, bitsStored = 0
        var pixelRepresentation = 0, samplesPerPixel = 1, planarConfiguration = 0
        var pixelDataOffset = -1

        while offset + 4 <= data.count {
            let group = readU16(data, offset, isBigEndian)
            let element = readU16(data, offset + 2, isBigEndian)

            if group == 0x7FE0 && element == 0x0010 {
                let (_, hs) = dicomDatasetValueLength(data, offset: offset, explicitVR: isExplicitVR, bigEndian: isBigEndian)
                pixelDataOffset = offset + hs
                break
            }

            let (vl, hs) = dicomDatasetValueLength(data, offset: offset, explicitVR: isExplicitVR, bigEndian: isBigEndian)
            let valStart = offset + hs
            if vl == 0xFFFF_FFFF || vl < 0 {
                offset = valStart + 1
                continue
            }

            switch (group, element) {
            case (0x0028, 0x0002): samplesPerPixel = Int(readU16(data, valStart, isBigEndian))
            case (0x0028, 0x0006): planarConfiguration = Int(readU16(data, valStart, isBigEndian))
            case (0x0028, 0x0010): rows = Int(readU16(data, valStart, isBigEndian))
            case (0x0028, 0x0011): columns = Int(readU16(data, valStart, isBigEndian))
            case (0x0028, 0x0100): bitsAllocated = Int(readU16(data, valStart, isBigEndian))
            case (0x0028, 0x0101): bitsStored = Int(readU16(data, valStart, isBigEndian))
            case (0x0028, 0x0103): pixelRepresentation = Int(readU16(data, valStart, isBigEndian))
            default: break
            }
            offset = valStart + vl
        }

        guard pixelDataOffset >= 0 else {
            throw J2KError.invalidParameter("DICOM file missing Pixel Data (7FE0,0010)")
        }
        guard rows > 0 && columns > 0 else {
            throw J2KError.invalidParameter("DICOM file has invalid Rows/Columns")
        }
        if bitsStored == 0 { bitsStored = bitsAllocated }

        let bytesPerSample = bitsAllocated / 8
        let pixelCount = rows * columns
        let frameSize = pixelCount * samplesPerPixel * bytesPerSample
        guard pixelDataOffset + frameSize <= data.count else {
            throw J2KError.invalidParameter("DICOM pixel data truncated")
        }

        let pixelData = data.subdata(in: pixelDataOffset..<(pixelDataOffset + frameSize))
        let componentCount = min(samplesPerPixel, 3)

        // Convert to 8-bit planar
        var planar = Data(count: pixelCount * componentCount)

        if bytesPerSample == 1 {
            // 8-bit data
            pixelData.withUnsafeBytes { src in
                planar.withUnsafeMutableBytes { dst in
                    let s = src.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let d = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    if samplesPerPixel == 1 {
                        for i in 0..<pixelCount { d[i] = s[i] }
                    } else if planarConfiguration == 1 {
                        for c in 0..<componentCount {
                            for i in 0..<pixelCount {
                                d[c * pixelCount + i] = s[c * pixelCount + i]
                            }
                        }
                    } else {
                        for i in 0..<pixelCount {
                            for c in 0..<componentCount {
                                d[c * pixelCount + i] = s[i * samplesPerPixel + c]
                            }
                        }
                    }
                }
            }
        } else {
            // 16-bit data — apply window/level to scale to 8-bit
            let signed = pixelRepresentation != 0
            pixelData.withUnsafeBytes { src in
                planar.withUnsafeMutableBytes { dst in
                    let d = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    // Find min/max for auto windowing
                    var minVal = Int.max, maxVal = Int.min
                    let totalSamples = pixelCount * samplesPerPixel
                    for i in 0..<totalSamples {
                        let byteOff = i * 2
                        guard byteOff + 1 < src.count else { break }
                        let lo = src[byteOff], hi = src[byteOff + 1]
                        var val: Int
                        if isBigEndian {
                            val = Int(UInt16(hi) | (UInt16(lo) << 8))
                        } else {
                            val = Int(UInt16(lo) | (UInt16(hi) << 8))
                        }
                        if signed && val >= (1 << (bitsStored - 1)) {
                            val -= (1 << bitsStored)
                        }
                        if val < minVal { minVal = val }
                        if val > maxVal { maxVal = val }
                    }
                    let range = max(1, maxVal - minVal)

                    for i in 0..<pixelCount {
                        for c in 0..<componentCount {
                            let sampleIdx: Int
                            if samplesPerPixel == 1 {
                                sampleIdx = i
                            } else if planarConfiguration == 1 {
                                sampleIdx = c * pixelCount + i
                            } else {
                                sampleIdx = i * samplesPerPixel + c
                            }
                            let byteOff = sampleIdx * 2
                            guard byteOff + 1 < src.count else { continue }
                            var val: Int
                            if isBigEndian {
                                val = Int(UInt16(src[byteOff + 1]) | (UInt16(src[byteOff]) << 8))
                            } else {
                                val = Int(UInt16(src[byteOff]) | (UInt16(src[byteOff + 1]) << 8))
                            }
                            if signed && val >= (1 << (bitsStored - 1)) {
                                val -= (1 << bitsStored)
                            }
                            let scaled = (val - minVal) * 255 / range
                            d[c * pixelCount + i] = UInt8(clamping: scaled)
                        }
                    }
                }
            }
        }

        return (planar, columns, rows, componentCount)
    }

    // MARK: - DICOM Helpers

    private static func readU16LE(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readU16(_ data: Data, _ offset: Int, _ bigEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return bigEndian
            ? UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            : UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readU32(_ data: Data, _ offset: Int, _ bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        if bigEndian {
            return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
                 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
        }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
             | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func dicomReadString(_ data: Data, _ offset: Int, _ length: Int) -> String? {
        guard offset + length <= data.count else { return nil }
        return String(data: data.subdata(in: offset..<(offset + length)), encoding: .ascii)
    }

    private static func dicomValueLength(_ data: Data, offset: Int, vr: String, bigEndian: Bool) -> (length: Int, headerSize: Int) {
        let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"]
        if longVRs.contains(vr) {
            return (Int(readU32(data, offset + 8, bigEndian)), 12)
        }
        return (Int(readU16(data, offset + 6, bigEndian)), 8)
    }

    private static func dicomDatasetValueLength(_ data: Data, offset: Int, explicitVR: Bool, bigEndian: Bool) -> (length: Int, headerSize: Int) {
        if !explicitVR {
            return (Int(readU32(data, offset + 4, false)), 8)
        }
        guard offset + 6 <= data.count else { return (0, 8) }
        let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)), encoding: .ascii) ?? ""
        return dicomValueLength(data, offset: offset, vr: vr, bigEndian: bigEndian)
    }
}
#endif
