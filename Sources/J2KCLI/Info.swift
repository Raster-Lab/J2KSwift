//
// Info.swift
// J2KSwift
//
/// Info command – display codestream and file-format metadata

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    /// Info command: display JPEG 2000 codestream information.
    static func infoCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printInfoHelp()
            return
        }

        // The file path may arrive as a positional argument or via -i/--input
        guard let filePath = options["_positional"] ?? options["i"] ?? options["input"] else {
            print("Error: Missing file argument")
            print("Usage: j2k info <file> [options]")
            exit(1)
        }

        let showMarkers  = options["markers"]  != nil
        let showBoxes    = options["boxes"]    != nil
        let jsonOutput   = options["json"]     != nil
        let validateOnly = options["validate"] != nil

        // Load file data
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        } catch {
            print("Error: Cannot read file '\(filePath)': \(error.localizedDescription)")
            exit(1)
        }

        // Detect container format
        let containerFormat = detectContainerFormat(data)

        // Locate the codestream (strip JP2 container if present)
        let codestreamData = extractCodestream(from: data, format: containerFormat)

        // Decode the codestream
        let decoder = J2KDecoder()
        let image: J2KImage
        do {
            image = try decoder.decode(codestreamData)
        } catch {
            if validateOnly {
                let msg = "Validation FAILED: \(error.localizedDescription)"
                if jsonOutput {
                    printJSON(["valid": false, "error": msg])
                } else {
                    print(msg)
                }
                exit(1)
            }
            print("Error: Failed to decode '\(filePath)': \(error.localizedDescription)")
            exit(1)
        }

        if validateOnly {
            if jsonOutput {
                printJSON(["valid": true, "file": filePath])
            } else {
                print("Valid: \(filePath)")
            }
            return
        }

        // Parse basic codestream header fields
        let isHTJ2K = detectHTJ2K(codestreamData)
        let markers = showMarkers ? extractMarkers(from: codestreamData) : []
        let boxes   = showBoxes   ? extractBoxes(from: data, format: containerFormat) : []

        if jsonOutput {
            var result: [String: Any] = [
                "file":        filePath,
                "format":      containerFormat,
                "width":       image.width,
                "height":      image.height,
                "components":  image.componentCount,
                "colourSpace": colourSpaceName(image.colorSpace),
                "isHTJ2K":     isHTJ2K,
                "fileSize":    data.count,
            ]
            // Component details
            var comps: [[String: Any]] = []
            for c in image.components {
                comps.append([
                    "index":      c.index,
                    "bitDepth":   c.bitDepth,
                    "signed":     c.signed,
                    "width":      c.width,
                    "height":     c.height,
                    "subsampleX": c.subsamplingX,
                    "subsampleY": c.subsamplingY,
                ])
            }
            result["componentDetails"] = comps
            if showMarkers { result["markers"] = markers }
            if showBoxes   { result["boxes"]   = boxes   }
            printJSON(result)
        } else {
            print("File:         \(filePath)")
            print("Format:       \(containerFormat)")
            print("File size:    \(formatBytes(data.count))")
            print("Dimensions:   \(image.width) × \(image.height)")
            print("Components:   \(image.componentCount)")
            print("Colour space: \(colourSpaceName(image.colorSpace))")
            print("HTJ2K:        \(isHTJ2K ? "yes" : "no")")
            print("")
            print("Components:")
            for c in image.components {
                let sub = c.isSubsampled ? " (subsampled \(c.subsamplingX)×\(c.subsamplingY))" : ""
                print("  [\(c.index)] \(c.width)×\(c.height), \(c.bitDepth)-bit \(c.signed ? "signed" : "unsigned")\(sub)")
            }
            if showMarkers {
                print("")
                print("Marker segments:")
                for m in markers {
                    print("  \(m)")
                }
            }
            if showBoxes {
                print("")
                print("JP2 boxes:")
                for b in boxes {
                    print("  \(b)")
                }
            }
        }
    }

    // MARK: - Helpers

    private static func printInfoHelp() {
        print("""
        j2k info - Display JPEG 2000 codestream information

        USAGE:
            j2k info <file> [options]

        OPTIONS:
            --markers       List codestream marker segments
            --boxes         List JP2/JPX file-format boxes
            --json          Output as JSON
            --validate      Perform a quick conformance check
        """)
    }

    /// Return a human-readable string for a colour space.
    static func colourSpaceName(_ cs: J2KColorSpace) -> String {
        switch cs {
        case .sRGB:              return "sRGB"
        case .grayscale:         return "Grayscale"
        case .yCbCr:             return "YCbCr"
        case .hdr:               return "HDR"
        case .hdrLinear:         return "HDR Linear"
        case .iccProfile:        return "ICC Profile"
        case .unknown:           return "Unknown"
        @unknown default:        return "Unknown"
        }
    }

    /// Detect the outer container format from the file magic bytes.
    static func detectContainerFormat(_ data: Data) -> String {
        guard data.count >= 12 else { return "j2k" }
        // JP2 / JPX signature: 0x0000000C 6A502020 (jP  )
        if data[0] == 0x00 && data[1] == 0x00 && data[2] == 0x00 && data[3] == 0x0C
            && data[4] == 0x6A && data[5] == 0x50 && data[6] == 0x20 && data[7] == 0x20 {
            return "jp2"
        }
        // Raw JPEG 2000 codestream: SOC marker FF 4F
        if data[0] == 0xFF && data[1] == 0x4F { return "j2k" }
        // HTJ2K SOC: same marker
        return "j2k"
    }

    /// Extract the raw codestream from a JP2 container, or return the data unchanged.
    static func extractCodestream(from data: Data, format: String) -> Data {
        guard format == "jp2" else { return data }
        // Walk boxes looking for 'jp2c' (contiguous codestream box)
        var offset = 0
        while offset + 8 <= data.count {
            let boxLen = Int(UInt32(bigEndian: data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }))
            guard let boxType = String(data: data.subdata(in: offset+4..<offset+8), encoding: .ascii) else { break }
            if boxType == "jp2c" {
                let payloadStart = offset + 8
                let payloadEnd   = (boxLen == 0) ? data.count : min(offset + boxLen, data.count)
                return data.subdata(in: payloadStart..<payloadEnd)
            }
            if boxLen <= 0 { break }
            offset += boxLen
        }
        return data
    }

    /// Heuristic HTJ2K detection: check for fast-mode markers in the codestream.
    static func detectHTJ2K(_ data: Data) -> Bool {
        // HTJ2K uses the same SOC (0xFF4F) but has the CAP segment (0xFF50)
        guard data.count > 4 else { return false }
        for i in 0..<min(data.count - 1, 256) {
            if data[i] == 0xFF && data[i + 1] == 0x50 { return true }
        }
        return false
    }

    /// Extract a list of marker names from a raw codestream.
    static func extractMarkers(from data: Data) -> [String] {
        let markerNames: [UInt8: String] = [
            0x4F: "SOC", 0x51: "SIZ", 0x52: "COD", 0x53: "COC",
            0x58: "PLM", 0x59: "PLT", 0x5C: "QCD", 0x5D: "QCC",
            0x5E: "RGN", 0x5F: "POC", 0x60: "PPM", 0x61: "PPT",
            0x63: "CRG", 0x64: "COM", 0x90: "SOT", 0x91: "SOP",
            0x92: "EPH", 0x93: "SOD", 0xD9: "EOC",
            0x50: "CAP", 0x54: "CPF",
        ]
        var markers: [String] = []
        var i = 0
        while i < data.count - 1 {
            if data[i] == 0xFF {
                let code = data[i + 1]
                if let name = markerNames[code] {
                    markers.append(String(format: "0x%04X %@", 0xFF00 | Int(code), name))
                }
                i += 2
            } else {
                i += 1
            }
        }
        return markers
    }

    /// Extract a list of JP2 box type strings.
    static func extractBoxes(from data: Data, format: String) -> [String] {
        guard format == "jp2" else { return [] }
        var boxes: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            let lenBytes = data.subdata(in: offset..<offset+4)
            let boxLen = Int(UInt32(bigEndian: lenBytes.withUnsafeBytes { $0.load(as: UInt32.self) }))
            guard let boxType = String(data: data.subdata(in: offset+4..<offset+8), encoding: .ascii) else { break }
            let size = (boxLen == 0) ? (data.count - offset) : boxLen
            boxes.append(String(format: "0x%06X  %@  (%d bytes)", offset, boxType, size))
            if boxLen <= 0 { break }
            offset += boxLen
        }
        return boxes
    }

    /// Serialise a dictionary to pretty-printed JSON and print it.
    static func printJSON(_ dict: [String: Any]) {
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: jsonData, encoding: .utf8) {
            print(str)
        }
    }
}
