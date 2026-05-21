//
// ViewerModel.swift
// J2KBenchApp — image viewer
//
// State + load logic for the Viewer tab. Decodes an image from one of
// three sources — an opened JPEG 2000 file, a benchmark fixture, or a
// round-tripped photo — and exposes the rendered result plus metadata
// and decode timing.

import Foundation
import SwiftUI
import PhotosUI
import J2KCore
import J2KCodec

// MARK: - Value types

/// Quality preset for the photo round-trip.
enum RoundTripQuality: String, CaseIterable, Identifiable {
    case lossless, high, medium
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lossless: return "Lossless"
        case .high:     return "High"
        case .medium:   return "Medium"
        }
    }
    var quality: Double {
        switch self {
        case .lossless: return 1.0
        case .high:     return 0.9
        case .medium:   return 0.5
        }
    }
}

/// Compression result for the photo round-trip.
struct RoundTripStats: Hashable {
    let rawBytes: Int            // raw pixel bytes of the source photo
    let codestreamBytes: Int
    let psnr: Double?            // nil ⇒ bit-exact (lossless)
    var compressionRatio: Double {
        codestreamBytes > 0 ? Double(rawBytes) / Double(codestreamBytes) : 0
    }
}

/// A decoded image ready to display, with everything the detail screen
/// needs. Identity is the `id` only, so it carries a non-Hashable
/// `UIImage` without trouble.
struct ViewerImage: Identifiable, Hashable {
    let id = UUID()
    let uiImage: UIImage
    let sourceLabel: String
    let width: Int
    let height: Int
    let componentCount: Int
    let bitDepth: Int
    let signed: Bool
    let colorSpace: String
    let fileBytes: Int?          // original file size (file source only)
    let codestreamBytes: Int
    let codestream: Data         // retained so the detail screen can re-time
    let decodeMS: Double
    let roundTrip: RoundTripStats?

    static func == (l: ViewerImage, r: ViewerImage) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A real medical image bundled with the app (DICOM-derived PGM).
struct MedicalSample: Identifiable {
    let resourceName: String     // bundle resource, without the .pgm extension
    let modality: String         // "CT", "MR", …
    let name: String             // human-readable modality name
    let dimensions: String       // "512×512"

    var id: String { resourceName }
    var menuLabel: String { "\(modality) \u{00b7} \(name) \u{00b7} \(dimensions)" }

    /// Bundled set — one real image per modality (~22 MB total). The
    /// PGM files are referenced from `Tests/Fixtures/CrossCodec/medical-real/`.
    static let all: [MedicalSample] = [
        .init(resourceName: "mr_real_small_174x192",   modality: "MR",
              name: "MRI", dimensions: "174\u{00d7}192"),
        .init(resourceName: "ct_real_small_512x512",   modality: "CT",
              name: "CT", dimensions: "512\u{00d7}512"),
        .init(resourceName: "xa_real_small_1024x1024", modality: "XA",
              name: "X-ray angiography", dimensions: "1024\u{00d7}1024"),
        .init(resourceName: "px_real_small_2459x1316", modality: "PX",
              name: "Panoramic X-ray", dimensions: "2459\u{00d7}1316"),
        .init(resourceName: "dx_real_small_2224x2798", modality: "DX",
              name: "Digital radiography", dimensions: "2224\u{00d7}2798"),
    ]
}

// MARK: - Model

@MainActor
final class ViewerModel: ObservableObject {
    @Published var current: ViewerImage?
    @Published var isLoading = false
    @Published var statusText = ""
    @Published var errorMessage: String?

    // MARK: Source 1 — opened JPEG 2000 or DICOM file

    func loadFile(_ url: URL) async {
        await run("Reading file\u{2026}") {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let fileData = try Data(contentsOf: url)

            // DICOM — decode the pixel data, then round-trip through
            // J2KSwift so the viewer always shows a real codec result.
            if let dicom = try DICOMReader.read(fileData) {
                return try await Self.roundTrip(
                    dicom,
                    sourceLabel: "\(url.lastPathComponent) \u{00b7} DICOM",
                    fileBytes: fileData.count,
                    encoder: J2KSampleSource.losslessHTEncoder())
            }

            // JPEG 2000 — decode the codestream directly.
            guard let codestream = Self.extractCodestream(from: fileData) else {
                throw ViewerError.unsupportedFile
            }
            let (image, ms) = try await Self.timedDecode(codestream)
            return try Self.makeViewerImage(
                image, codestream: codestream, decodeMS: ms,
                sourceLabel: url.lastPathComponent,
                fileBytes: fileData.count, roundTrip: nil)
        }
    }

    // MARK: Source 4 — bundled real medical image

    func loadMedical(_ sample: MedicalSample) async {
        await run("Loading \(sample.modality) sample\u{2026}") {
            guard let url = Bundle.main.url(forResource: sample.resourceName,
                                            withExtension: "pgm"),
                  let pgmData = try? Data(contentsOf: url),
                  let source = J2KSampleSource.j2kImage(fromPGM: pgmData)
            else { throw ViewerError.missingMedicalSample }

            return try await Self.roundTrip(
                source,
                sourceLabel: "\(sample.modality) \(sample.dimensions) "
                           + "\u{00b7} medical sample",
                fileBytes: nil,
                encoder: J2KSampleSource.losslessHTEncoder())
        }
    }

    // MARK: Source 2 — benchmark fixture

    func loadFixture(_ fixture: BenchFixture) async {
        await run("Encoding \(fixture.label)\u{2026}") {
            let source = J2KSampleSource.synthesize(fixture)
            return try await Self.roundTrip(
                source,
                sourceLabel: "\(fixture.label) \u{00b7} benchmark fixture",
                fileBytes: nil,
                encoder: J2KSampleSource.losslessHTEncoder())
        }
    }

    // MARK: Source 3 — photo round-trip

    func loadPhoto(_ item: PhotosPickerItem, quality: RoundTripQuality) async {
        await run("Loading photo\u{2026}") {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiSource = UIImage(data: data),
                  let cgSource = uiSource.cgImage,
                  let source = J2KSampleSource.j2kImage(from: cgSource)
            else { throw ViewerError.badPhoto }

            let encoder = quality == .lossless
                ? J2KSampleSource.losslessHTEncoder()
                : J2KSampleSource.lossyHTEncoder(quality: quality.quality)
            return try await Self.roundTrip(
                source,
                sourceLabel: "Photo round-trip \u{00b7} \(quality.label)",
                fileBytes: nil, encoder: encoder)
        }
    }

    // MARK: - Shared plumbing

    /// Run a loader: flip `isLoading`, surface the result or a friendly
    /// error. Keeps the three `load*` methods to their essentials.
    private func run(_ status: String,
                     _ body: @escaping () async throws -> ViewerImage) async {
        isLoading = true
        statusText = status
        errorMessage = nil
        defer { isLoading = false }
        do {
            current = try await body()
        } catch {
            errorMessage = Self.friendly(error)
        }
    }

    private static func timedDecode(_ codestream: Data) async throws
        -> (J2KImage, Double) {
        let decoder = J2KDecoder()
        let t0 = DispatchTime.now().uptimeNanoseconds
        let image = try await decoder.decode(codestream)
        let t1 = DispatchTime.now().uptimeNanoseconds
        return (image, Double(t1 - t0) / 1_000_000)
    }

    /// Encode a source image, decode it back (timed), and package the
    /// result with compression-ratio + PSNR stats. Used by the fixture,
    /// photo, medical-sample and DICOM sources — all of which start
    /// from raw pixels rather than an existing codestream.
    private static func roundTrip(_ source: J2KImage, sourceLabel: String,
                                  fileBytes: Int?, encoder: J2KEncoder)
        async throws -> ViewerImage {
        let codestream = try await encoder.encode(source)
        let (decoded, ms) = try await timedDecode(codestream)
        let rawBytes = source.components.reduce(0) { $0 + $1.data.count }
        let stats = RoundTripStats(
            rawBytes: rawBytes,
            codestreamBytes: codestream.count,
            psnr: J2KSampleSource.psnr(source, decoded))
        return try makeViewerImage(
            decoded, codestream: codestream, decodeMS: ms,
            sourceLabel: sourceLabel, fileBytes: fileBytes, roundTrip: stats)
    }

    private static func makeViewerImage(
        _ image: J2KImage, codestream: Data, decodeMS: Double,
        sourceLabel: String, fileBytes: Int?, roundTrip: RoundTripStats?
    ) throws -> ViewerImage {
        guard let ui = J2KImageRenderer.uiImage(from: image) else {
            throw ViewerError.renderFailed
        }
        let first = image.components.first
        return ViewerImage(
            uiImage: ui,
            sourceLabel: sourceLabel,
            width: image.width,
            height: image.height,
            componentCount: image.components.count,
            bitDepth: first?.bitDepth ?? 0,
            signed: first?.signed ?? false,
            colorSpace: colorSpaceLabel(image.colorSpace),
            fileBytes: fileBytes,
            codestreamBytes: codestream.count,
            codestream: codestream,
            decodeMS: decodeMS,
            roundTrip: roundTrip)
    }

    private static func colorSpaceLabel(_ cs: J2KColorSpace) -> String {
        switch cs {
        case .sRGB:       return "sRGB"
        case .grayscale:  return "Grayscale"
        case .yCbCr:      return "YCbCr"
        case .hdr:        return "HDR"
        case .hdrLinear:  return "HDR (linear)"
        case .iccProfile: return "ICC profile"
        case .unknown:    return "Unknown"
        }
    }

    private static func friendly(_ error: Error) -> String {
        switch error {
        case ViewerError.unsupportedFile:
            return "Unsupported file \u{2014} pick a JPEG 2000 "
                 + "(.jp2 / .j2k / .jph) or an uncompressed DICOM (.dcm) image."
        case ViewerError.badPhoto:
            return "That photo couldn't be read."
        case ViewerError.renderFailed:
            return "The image decoded but couldn't be rendered for display."
        case ViewerError.missingMedicalSample:
            return "That bundled medical image is missing or unreadable."
        case let dicom as DICOMReader.DICOMError:
            return dicom.errorDescription ?? "Unsupported DICOM file."
        case let j2k as J2KError:
            return "Decode failed \u{2014} the file may be malformed. (\(j2k))"
        default:
            return error.localizedDescription
        }
    }

    /// Extract a raw codestream from arbitrary JPEG 2000 file data: a
    /// raw codestream (SOC marker `FF 4F`) passes straight through; a
    /// JP2/JPH/JPX box file is walked for its `jp2c` contiguous-
    /// codestream box. Mirrors `J2KFileReader`'s private extractor.
    static func extractCodestream(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }

        // Raw codestream — starts with the SOC marker.
        if bytes[0] == 0xFF, bytes[1] == 0x4F { return data }

        // Box walk for the 'jp2c' box (0x6A 0x70 0x32 0x63).
        var offset = 0
        while offset + 8 <= bytes.count {
            let length = Int(UInt32(bytes[offset]) << 24
                           | UInt32(bytes[offset + 1]) << 16
                           | UInt32(bytes[offset + 2]) << 8
                           | UInt32(bytes[offset + 3]))
            let type = Array(bytes[(offset + 4)..<(offset + 8)])

            if type == [0x6A, 0x70, 0x32, 0x63] {
                let start = offset + 8
                let len = length == 0 ? bytes.count - start : length - 8
                guard len > 0, start + len <= bytes.count else { return nil }
                return Data(bytes[start..<(start + len)])
            }

            var boxLength = length
            if length == 1, offset + 16 <= bytes.count {
                var ext: UInt64 = 0
                for k in 0..<8 { ext = (ext << 8) | UInt64(bytes[offset + 8 + k]) }
                boxLength = Int(truncatingIfNeeded: ext)
            } else if length == 0 {
                boxLength = bytes.count - offset
            }
            guard boxLength > 0 else { return nil }
            offset += boxLength
        }
        return nil
    }
}

enum ViewerError: Error {
    case unsupportedFile
    case badPhoto
    case renderFailed
    case missingMedicalSample
}
