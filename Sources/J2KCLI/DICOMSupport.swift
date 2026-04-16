//
// DICOMSupport.swift
// J2KSwift
//
/// Minimal DICOM pixel-data extractor (input only).
///
/// Parses uncompressed DICOM files with explicit and implicit VR, in both
/// little-endian and big-endian transfer syntaxes, and can also fall back to
/// a local Python helper for selected compressed transfer syntaxes. Strips all
/// metadata and returns only the pixel data as a `J2KImage`.
///
/// This code lives in the CLI target only — no DICOM dependency is added to
/// the J2KSwift library (per ADR-004).

import Foundation
import J2KCore

extension J2KCLI {

    // MARK: - Transfer Syntax

    enum DICOMTransferSyntax: Sendable, Equatable {
        case implicitVRLittleEndian
        case explicitVRLittleEndian
        case explicitVRBigEndian
    }

    struct DICOMTransferSyntaxInfo: Sendable, Equatable {
        let byteOrderSyntax: DICOMTransferSyntax
        let uid: String
        let isCompressed: Bool
        let isJPEG2000: Bool
    }

    // MARK: - Public API

    /// Load a DICOM file, stripping all metadata and returning the pixel data
    /// as a `J2KImage`.
    ///
    /// Uncompressed transfer syntaxes are parsed directly. Selected compressed
    /// non-JPEG 2000 syntaxes can be decompressed through the workspace Python
    /// helper, while JPEG 2000 transfer syntaxes produce a helpful error
    /// directing the user to `j2k decode`.
    static func loadDICOM(_ data: Data) throws -> J2KImage {
        // 1. Validate preamble + magic
        guard data.count >= 132 + 4 else {
            throw J2KError.invalidParameter("Not a valid DICOM file: too small")
        }
        let magic = String(data: data.subdata(in: 128..<132), encoding: .ascii)
        guard magic == "DICM" else {
            throw J2KError.invalidParameter(
                "Not a valid DICOM file (missing DICM prefix). " +
                "Ensure the file includes the 128-byte preamble.")
        }

        // 2. Read File Meta Information (group 0002, always Explicit VR LE)
        var offset = 132
        var transferSyntaxInfo = DICOMTransferSyntaxInfo(
            byteOrderSyntax: .explicitVRLittleEndian,
            uid: "1.2.840.10008.1.2.1",
            isCompressed: false,
            isJPEG2000: false
        )

        // Read tags in group 0002 to find Transfer Syntax UID
        while offset + 8 <= data.count {
            let group   = dcmReadU16LE(data, offset: offset)
            let element = dcmReadU16LE(data, offset: offset + 2)

            if group != 0x0002 { break }

            // Group 0002 is always Explicit VR Little Endian
            let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)), encoding: .ascii) ?? ""
            let (valueLength, headerSize) = dcmValueLength(data, offset: offset, vr: vr, bigEndian: false)
            let valueStart = offset + headerSize

            if element == 0x0010 {
                // Transfer Syntax UID
                if let tsUID = dcmReadString(data, offset: valueStart, length: valueLength) {
                    transferSyntaxInfo = dicomTransferSyntaxInfo(for: tsUID)
                }
            }

            offset = valueStart + valueLength
        }

        // 3. Parse dataset to extract pixel-interpretation tags
        let bigEndian = (transferSyntaxInfo.byteOrderSyntax == .explicitVRBigEndian)
        let explicitVR = (transferSyntaxInfo.byteOrderSyntax != .implicitVRLittleEndian)

        var rows = 0
        var columns = 0
        var bitsAllocated = 16
        var bitsStored = 0
        var pixelRepresentation = 0  // 0 = unsigned, 1 = signed
        var samplesPerPixel = 1
        var photometricInterpretation = ""
        var planarConfiguration = 0
        var numberOfFrames = 1
        var pixelDataOffset = -1
        var pixelDataLength = 0

        while offset + 4 <= data.count {
            let group   = dcmReadU16(data, offset: offset, bigEndian: bigEndian)
            let element = dcmReadU16(data, offset: offset + 2, bigEndian: bigEndian)
            let tag = (group, element)

            // Pixel Data tag — stop here
            if tag == (0x7FE0, 0x0010) {
                let (vl, hs) = dcmDatasetValueLength(data, offset: offset, explicitVR: explicitVR, bigEndian: bigEndian)
                pixelDataOffset = offset + hs
                pixelDataLength = vl

                if transferSyntaxInfo.isJPEG2000 {
                    throw J2KError.invalidParameter(
                        "Input is already JPEG 2000 compressed (TS: \(transferSyntaxInfo.uid)). Use j2k decode instead."
                    )
                }
                if transferSyntaxInfo.isCompressed {
                    return try loadCompressedDICOM(data, transferSyntaxInfo: transferSyntaxInfo)
                }
                if vl == 0xFFFF_FFFF {
                    throw J2KError.invalidParameter(
                        "Encapsulated pixel data is not supported for transfer syntax \(transferSyntaxInfo.uid)."
                    )
                }
                break
            }

            // Read value
            let (vl, hs) = dcmDatasetValueLength(data, offset: offset, explicitVR: explicitVR, bigEndian: bigEndian)
            let valueStart = offset + hs

            if vl == 0xFFFF_FFFF {
                // Undefined-length sequence — skip it
                offset = skipDICOMSequence(data, from: valueStart, bigEndian: bigEndian)
                continue
            }

            switch tag {
            case (0x0028, 0x0002):
                samplesPerPixel = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0004):
                photometricInterpretation = dcmReadString(data, offset: valueStart, length: vl) ?? ""
            case (0x0028, 0x0006):
                planarConfiguration = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0008):
                if let s = dcmReadString(data, offset: valueStart, length: vl), let n = Int(s.trimmingCharacters(in: .whitespaces)) {
                    numberOfFrames = n
                }
            case (0x0028, 0x0010):
                rows = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0011):
                columns = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0100):
                bitsAllocated = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0101):
                bitsStored = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0102):
                break  // High Bit — parsed but not needed
            case (0x0028, 0x0103):
                pixelRepresentation = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            default:
                break
            }

            offset = valueStart + vl
        }

        // Validate
        guard pixelDataOffset >= 0 else {
            throw J2KError.invalidParameter("DICOM file missing Pixel Data tag (7FE0,0010)")
        }

        let effectiveBitsStored = bitsStored == 0 ? bitsAllocated : bitsStored
        let bytesPerSample = max(1, (bitsAllocated + 7) / 8)
        let frameCount = max(1, numberOfFrames)
        let frameSize = columns * rows * samplesPerPixel * bytesPerSample
        let totalPixelBytes = frameSize * frameCount
        let availablePixelBytes: Int
        if pixelDataLength == 0xFFFF_FFFF || pixelDataLength <= 0 {
            availablePixelBytes = data.count - pixelDataOffset
        } else {
            availablePixelBytes = min(pixelDataLength, data.count - pixelDataOffset)
        }

        guard totalPixelBytes > 0, availablePixelBytes >= totalPixelBytes else {
            throw J2KError.invalidParameter("DICOM pixel data truncated")
        }

        var pixelData = data.subdata(in: pixelDataOffset..<(pixelDataOffset + totalPixelBytes))

        // Canonicalize multi-byte samples to the CLI's internal big-endian layout.
        if !bigEndian && bytesPerSample == 2 {
            let sampleCount = pixelData.count / 2
            for i in 0..<sampleCount {
                pixelData.swapAt(i * 2, i * 2 + 1)
            }
        }

        return try makeDICOMImage(
            rows: rows,
            columns: columns,
            bitsAllocated: bitsAllocated,
            bitsStored: effectiveBitsStored,
            pixelRepresentation: pixelRepresentation,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometricInterpretation,
            planarConfiguration: planarConfiguration,
            numberOfFrames: numberOfFrames,
            pixelData: pixelData
        )
    }

    // MARK: - Transfer Syntax Parsing

    static func dicomTransferSyntaxInfo(for uid: String) -> DICOMTransferSyntaxInfo {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        let isJPEG2000 = trimmed.hasPrefix("1.2.840.10008.1.2.4.90") || trimmed.hasPrefix("1.2.840.10008.1.2.4.91")
        let isCompressed = isJPEG2000
            || trimmed.hasPrefix("1.2.840.10008.1.2.4")
            || trimmed.hasPrefix("1.2.840.10008.1.2.5")

        let byteOrderSyntax: DICOMTransferSyntax
        switch trimmed {
        case "1.2.840.10008.1.2":
            byteOrderSyntax = .implicitVRLittleEndian
        case "1.2.840.10008.1.2.2":
            byteOrderSyntax = .explicitVRBigEndian
        default:
            byteOrderSyntax = .explicitVRLittleEndian
        }

        return DICOMTransferSyntaxInfo(
            byteOrderSyntax: byteOrderSyntax,
            uid: trimmed,
            isCompressed: isCompressed,
            isJPEG2000: isJPEG2000
        )
    }

    private static func loadCompressedDICOM(
        _ data: Data,
        transferSyntaxInfo: DICOMTransferSyntaxInfo
    ) throws -> J2KImage {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "j2k-dicom-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let inputURL = temporaryDirectory.appendingPathComponent("input.dcm")
        let metadataURL = temporaryDirectory.appendingPathComponent("metadata.json")
        let pixelURL = temporaryDirectory.appendingPathComponent("pixels.bin")
        try data.write(to: inputURL)

        let pythonExecutable = try resolveCompressedDICOMPythonExecutable()
        let script = """
import json
import sys
from pathlib import Path

import numpy as np
import pydicom

input_path, metadata_path, pixel_path = sys.argv[1:4]
ds = pydicom.dcmread(input_path)
arr = ds.pixel_array
frames = int(getattr(ds, \"NumberOfFrames\", 1) or 1)
samples_per_pixel = int(getattr(ds, \"SamplesPerPixel\", 1) or 1)
arr = np.ascontiguousarray(arr)
if arr.dtype.itemsize == 2:
    if arr.dtype.kind == \"u\":
        arr = arr.astype(\">u2\", copy=False)
    elif arr.dtype.kind == \"i\":
        arr = arr.astype(\">i2\", copy=False)
elif arr.dtype.itemsize == 4:
    if arr.dtype.kind == \"u\":
        arr = arr.astype(\">u4\", copy=False)
    elif arr.dtype.kind == \"i\":
        arr = arr.astype(\">i4\", copy=False)
Path(pixel_path).write_bytes(arr.tobytes(order=\"C\"))
metadata = {
    \"rows\": int(getattr(ds, \"Rows\", arr.shape[0] if getattr(arr, \"ndim\", 0) >= 1 else 0)),
    \"columns\": int(getattr(ds, \"Columns\", arr.shape[1] if getattr(arr, \"ndim\", 0) >= 2 else 0)),
    \"bitsAllocated\": int(getattr(ds, \"BitsAllocated\", arr.dtype.itemsize * 8)),
    \"bitsStored\": int(getattr(ds, \"BitsStored\", getattr(ds, \"BitsAllocated\", arr.dtype.itemsize * 8))),
    \"pixelRepresentation\": int(getattr(ds, \"PixelRepresentation\", 0)),
    \"samplesPerPixel\": samples_per_pixel,
    \"photometricInterpretation\": str(getattr(ds, \"PhotometricInterpretation\", \"\")),
    \"planarConfiguration\": 0,
    \"numberOfFrames\": frames,
}
Path(metadata_path).write_text(json.dumps(metadata), encoding=\"utf-8\")
"""

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        if pythonExecutable.contains("/") {
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments = ["-c", script, inputURL.path, metadataURL.path, pixelURL.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [pythonExecutable, "-c", script, inputURL.path, metadataURL.path, pixelURL.path]
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw J2KError.invalidParameter(
                "Compressed DICOM transfer syntax (\(transferSyntaxInfo.uid)) could not start the Python decompression helper: \(error.localizedDescription)"
            )
        }

        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw J2KError.invalidParameter(
                "Compressed DICOM transfer syntax (\(transferSyntaxInfo.uid)) requires Python decompression support. Install pydicom with JPEG plugins or set J2K_DICOM_PYTHON. \(details)"
            )
        }

        struct PythonDecodedDICOMMetadata: Decodable {
            let rows: Int
            let columns: Int
            let bitsAllocated: Int
            let bitsStored: Int
            let pixelRepresentation: Int
            let samplesPerPixel: Int
            let photometricInterpretation: String
            let planarConfiguration: Int
            let numberOfFrames: Int
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(PythonDecodedDICOMMetadata.self, from: metadataData)
        let pixelData = try Data(contentsOf: pixelURL)

        return try makeDICOMImage(
            rows: metadata.rows,
            columns: metadata.columns,
            bitsAllocated: metadata.bitsAllocated,
            bitsStored: metadata.bitsStored,
            pixelRepresentation: metadata.pixelRepresentation,
            samplesPerPixel: metadata.samplesPerPixel,
            photometricInterpretation: metadata.photometricInterpretation,
            planarConfiguration: metadata.planarConfiguration,
            numberOfFrames: metadata.numberOfFrames,
            pixelData: pixelData
        )
    }

    private static func resolveCompressedDICOMPythonExecutable() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if let explicit = environment["J2K_DICOM_PYTHON"], !explicit.isEmpty {
            candidates.append(explicit)
        }
        if let virtualEnv = environment["VIRTUAL_ENV"], !virtualEnv.isEmpty {
            candidates.append(URL(fileURLWithPath: virtualEnv).appendingPathComponent("bin/python").path)
        }

        var searchDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<6 {
            candidates.append(searchDirectory.appendingPathComponent(".venv/bin/python").path)
            let parent = searchDirectory.deletingLastPathComponent()
            if parent.path == searchDirectory.path { break }
            searchDirectory = parent
        }

        candidates.append(contentsOf: ["/usr/bin/python3", "python3", "python"])

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if pythonEnvironmentSupportsDICOMDecompression(candidate) {
                return candidate
            }
        }

        throw J2KError.invalidParameter(
            "Compressed DICOM transfer syntaxes require Python with pydicom, numpy, and JPEG plugins. Set J2K_DICOM_PYTHON or use a workspace .venv."
        )
    }

    private static func pythonEnvironmentSupportsDICOMDecompression(_ candidate: String) -> Bool {
        let process = Process()
        if candidate.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: candidate) else { return false }
            process.executableURL = URL(fileURLWithPath: candidate)
            process.arguments = ["-c", "import pydicom, numpy"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [candidate, "-c", "import pydicom, numpy"]
        }

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func makeDICOMImage(
        rows: Int,
        columns: Int,
        bitsAllocated: Int,
        bitsStored: Int,
        pixelRepresentation: Int,
        samplesPerPixel: Int,
        photometricInterpretation: String,
        planarConfiguration: Int,
        numberOfFrames: Int,
        pixelData: Data
    ) throws -> J2KImage {
        guard rows > 0 && columns > 0 else {
            throw J2KError.invalidParameter("DICOM file missing Rows/Columns tags")
        }

        let frameCount = max(1, numberOfFrames)
        let signed = pixelRepresentation != 0
        let bytesPerSample = max(1, (bitsAllocated + 7) / 8)
        let pixelCount = columns * rows
        let frameByteCount = pixelCount * max(1, samplesPerPixel) * bytesPerSample

        guard frameByteCount > 0, pixelData.count >= frameByteCount * frameCount else {
            throw J2KError.invalidParameter("DICOM pixel data truncated")
        }

        let mosaicLayout = dicomFrameMosaicLayout(frameCount: frameCount)
        let mosaicWidth = columns * mosaicLayout.columns
        let mosaicHeight = rows * mosaicLayout.rows

        if frameCount > 1,
           let warnData = "Warning: DICOM file has \(frameCount) frames; composing a \(mosaicLayout.columns)x\(mosaicLayout.rows) mosaic for CLI processing (\(mosaicWidth)x\(mosaicHeight)).\n".data(using: .utf8) {
            FileHandle.standardError.write(warnData)
        }

        var mosaicPlanes = Array(
            repeating: Data(count: mosaicWidth * mosaicHeight * bytesPerSample),
            count: max(1, samplesPerPixel)
        )

        for frameIndex in 0..<frameCount {
            let frameStart = frameIndex * frameByteCount
            let frameEnd = frameStart + frameByteCount
            let frameData = pixelData.subdata(in: frameStart..<frameEnd)
            let framePlanes = splitDICOMFrameIntoPlanes(
                frameData,
                samplesPerPixel: max(1, samplesPerPixel),
                planarConfiguration: planarConfiguration,
                pixelCount: pixelCount,
                bytesPerSample: bytesPerSample
            )

            let tileColumn = frameIndex % mosaicLayout.columns
            let tileRow = frameIndex / mosaicLayout.columns
            let destinationX = tileColumn * columns
            let destinationY = tileRow * rows

            for sampleIndex in 0..<framePlanes.count {
                copyDICOMFramePlane(
                    framePlanes[sampleIndex],
                    into: &mosaicPlanes[sampleIndex],
                    frameWidth: columns,
                    frameHeight: rows,
                    bytesPerSample: bytesPerSample,
                    mosaicWidth: mosaicWidth,
                    destinationX: destinationX,
                    destinationY: destinationY
                )
            }
        }

        let components = mosaicPlanes.enumerated().map { index, planeData in
            J2KComponent(
                index: index,
                bitDepth: bitsStored,
                signed: signed,
                width: mosaicWidth,
                height: mosaicHeight,
                subsamplingX: 1,
                subsamplingY: 1,
                data: planeData
            )
        }

        let interpretation = photometricInterpretation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let colorSpace: J2KColorSpace
        switch interpretation {
        case "RGB", "YBR_FULL", "YBR_FULL_422":
            colorSpace = .sRGB
        default:
            colorSpace = .grayscale
        }

        return J2KImage(
            width: mosaicWidth,
            height: mosaicHeight,
            components: components,
            colorSpace: colorSpace
        )
    }

    private static func dicomFrameMosaicLayout(frameCount: Int) -> (columns: Int, rows: Int) {
        guard frameCount > 1 else { return (1, 1) }

        let mosaicColumns = max(1, Int(ceil(sqrt(Double(frameCount)))))
        let mosaicRows = max(1, (frameCount + mosaicColumns - 1) / mosaicColumns)
        return (mosaicColumns, mosaicRows)
    }

    private static func splitDICOMFrameIntoPlanes(
        _ frameData: Data,
        samplesPerPixel: Int,
        planarConfiguration: Int,
        pixelCount: Int,
        bytesPerSample: Int
    ) -> [Data] {
        if samplesPerPixel == 1 {
            return [frameData]
        }

        if planarConfiguration == 1 {
            let planeSize = pixelCount * bytesPerSample
            return (0..<samplesPerPixel).map { sampleIndex in
                let start = sampleIndex * planeSize
                let end = min(start + planeSize, frameData.count)
                return frameData.subdata(in: start..<end)
            }
        }

        var planes = Array(repeating: Data(count: pixelCount * bytesPerSample), count: samplesPerPixel)
        for pixelIndex in 0..<pixelCount {
            for sampleIndex in 0..<samplesPerPixel {
                let sourceOffset = (pixelIndex * samplesPerPixel + sampleIndex) * bytesPerSample
                let destinationOffset = pixelIndex * bytesPerSample
                for byteIndex in 0..<bytesPerSample where sourceOffset + byteIndex < frameData.count {
                    planes[sampleIndex][destinationOffset + byteIndex] = frameData[sourceOffset + byteIndex]
                }
            }
        }
        return planes
    }

    private static func copyDICOMFramePlane(
        _ framePlane: Data,
        into destinationPlane: inout Data,
        frameWidth: Int,
        frameHeight: Int,
        bytesPerSample: Int,
        mosaicWidth: Int,
        destinationX: Int,
        destinationY: Int
    ) {
        let sourceRowByteCount = frameWidth * bytesPerSample
        for row in 0..<frameHeight {
            let sourceStart = row * sourceRowByteCount
            let sourceEnd = min(sourceStart + sourceRowByteCount, framePlane.count)
            let destinationStart = ((destinationY + row) * mosaicWidth + destinationX) * bytesPerSample
            var writeIndex = destinationStart
            for byte in framePlane[sourceStart..<sourceEnd] where writeIndex < destinationPlane.count {
                destinationPlane[writeIndex] = byte
                writeIndex += 1
            }
        }
    }

    // MARK: - Low-level DICOM helpers

    private static func dcmReadU16LE(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func dcmReadU16(_ data: Data, offset: Int, bigEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        if bigEndian {
            return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func dcmReadU32(_ data: Data, offset: Int, bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        if bigEndian {
            return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
                 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
        }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
             | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func dcmReadString(_ data: Data, offset: Int, length: Int) -> String? {
        guard offset + length <= data.count else { return nil }
        return String(data: data.subdata(in: offset..<(offset + length)), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(["\0"])))
    }

    /// Read value length for a tag in File Meta Information (always Explicit VR LE).
    private static func dcmValueLength(_ data: Data, offset: Int, vr: String, bigEndian: Bool) -> (length: Int, headerSize: Int) {
        // Explicit VR with 4-byte length for OB, OD, OF, OL, OW, SQ, UC, UN, UR, UT
        let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"]
        if longVRs.contains(vr) {
            // 4 bytes tag + 2 VR + 2 reserved + 4 length
            let length = Int(dcmReadU32(data, offset: offset + 8, bigEndian: bigEndian))
            return (length, 12)
        } else {
            // 4 bytes tag + 2 VR + 2 length
            let length = Int(dcmReadU16(data, offset: offset + 6, bigEndian: bigEndian))
            return (length, 8)
        }
    }

    /// Read value length for a tag in the dataset (may be explicit or implicit VR).
    private static func dcmDatasetValueLength(_ data: Data, offset: Int, explicitVR: Bool, bigEndian: Bool) -> (length: Int, headerSize: Int) {
        if !explicitVR {
            // Implicit VR: tag (4) + length (4)
            let length = Int(dcmReadU32(data, offset: offset + 4, bigEndian: false))  // implicit is always LE
            return (length, 8)
        }

        guard offset + 6 <= data.count else { return (0, 8) }
        let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)), encoding: .ascii) ?? ""
        return dcmValueLength(data, offset: offset, vr: vr, bigEndian: bigEndian)
    }

    /// Skip a DICOM sequence with undefined length.
    private static func skipDICOMSequence(_ data: Data, from start: Int, bigEndian: Bool) -> Int {
        var pos = start
        while pos + 8 <= data.count {
            let itemTag = (dcmReadU16(data, offset: pos, bigEndian: bigEndian),
                          dcmReadU16(data, offset: pos + 2, bigEndian: bigEndian))
            let itemLen = Int(dcmReadU32(data, offset: pos + 4, bigEndian: bigEndian))

            if itemTag == (0xFFFE, 0xE0DD) {
                // Sequence Delimitation Item
                return pos + 8
            }

            if itemLen == 0xFFFF_FFFF {
                // Undefined length item — scan for Item Delimitation
                pos += 8
                while pos + 8 <= data.count {
                    let innerTag = (dcmReadU16(data, offset: pos, bigEndian: bigEndian),
                                   dcmReadU16(data, offset: pos + 2, bigEndian: bigEndian))
                    if innerTag == (0xFFFE, 0xE00D) {
                        pos += 8
                        break
                    }
                    // Skip inner element
                    let (vl, hs) = dcmDatasetValueLength(data, offset: pos, explicitVR: true, bigEndian: bigEndian)
                    if vl == 0xFFFF_FFFF {
                        pos = skipDICOMSequence(data, from: pos + hs, bigEndian: bigEndian)
                    } else {
                        pos += hs + vl
                    }
                }
            } else {
                pos += 8 + itemLen
            }
        }
        return pos
    }
}
