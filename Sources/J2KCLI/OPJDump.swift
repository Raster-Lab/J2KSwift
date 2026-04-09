//
// OPJDump.swift
// J2KSwift
//
/// OpenJPEG-compatible `dump` command.
///
/// Mirrors the `opj_dump` CLI from OpenJPEG, accepting the same flags
/// (`-i`, `-o`, `-v`, `-f`, `-ImgDir`) so that users familiar with
/// OpenJPEG can switch to J2KSwift with minimal friction.
///
/// Dumps JPEG 2000 codestream info to stdout or a given file.

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    // MARK: - Entry point

    static func opjDumpCommand(_ args: [String]) async throws {
        let opts = parseOPJDumpArguments(args)

        if opts["h"] != nil || opts["help"] != nil {
            printOPJDumpHelp()
            return
        }

        guard let inputPath = opts["i"] else {
            printToStderr("[ERROR] Required parameter is missing")
            printToStderr("Example: j2k dump -i image.j2k")
            printToStderr("   Help: j2k dump -h")
            exit(1)
        }

        let outputFile = opts["o"]
        let verbose = opts["v"] != nil

        // Validate input format
        let inputURL = URL(fileURLWithPath: inputPath)
        let inExt = inputURL.pathExtension.lowercased()
        let supportedFormats: Set<String> = ["j2k", "jp2", "jpt", "j2c", "jpc", "jph", "jhc"]
        guard supportedFormats.contains(inExt) else {
            printToStderr("[ERROR] Unknown input file format: \(inputPath)")
            printToStderr("Known extensions are <J2K|JP2|JPT|J2C|JPC|JPH|JHC>")
            exit(1)
        }

        // Load file data
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        } catch {
            printToStderr("[ERROR] Failed to create the stream from the file \(inputPath)")
            exit(1)
        }

        // Detect container format and extract codestream
        let containerFormat = detectContainerFormat(data)
        let codestreamData = extractCodestream(from: data, format: containerFormat)

        // Decode the header
        let decoder = J2KDecoder()
        let image: J2KImage
        do {
            image = try decoder.decode(codestreamData)
        } catch {
            printToStderr("[ERROR] Failed to read the header: \(error)")
            exit(1)
        }

        // Build dump output
        var output = ""

        output += "=== JPEG 2000 Codestream Information ===\n"
        output += "\n"
        output += "Image {\n"
        output += "  x0=0, y0=0, x1=\(image.width), y1=\(image.height)\n"
        output += "  numcomps=\(image.componentCount)\n"
        output += "}\n"
        output += "\n"

        // Component info
        for c in image.components {
            output += "Component \(c.index) {\n"
            output += "  dx=\(c.subsamplingX), dy=\(c.subsamplingY)\n"
            output += "  prec=\(c.bitDepth)\n"
            output += "  sgnd=\(c.signed ? 1 : 0)\n"
            output += "  w=\(c.width), h=\(c.height)\n"
            output += "}\n"
        }
        output += "\n"

        // Codestream info
        let isHTJ2K = detectHTJ2K(codestreamData)
        output += "Codestream {\n"
        output += "  format=\(containerFormat)\n"
        output += "  HTJ2K=\(isHTJ2K ? "yes" : "no")\n"
        output += "  fileSize=\(data.count)\n"
        output += "  codestreamSize=\(codestreamData.count)\n"
        output += "}\n"

        // Markers
        let markers = extractMarkers(from: codestreamData)
        output += "\n"
        output += "Marker segments {\n"
        for m in markers {
            output += "  \(m)\n"
        }
        output += "}\n"

        // Boxes (if JP2 container)
        if containerFormat == "jp2" {
            let boxes = extractBoxes(from: data, format: containerFormat)
            output += "\n"
            output += "JP2 boxes {\n"
            for b in boxes {
                output += "  \(b)\n"
            }
            output += "}\n"
        }

        if verbose {
            output += "\n"
            output += "Color space: \(colourSpaceName(image.colorSpace))\n"
        }

        // Write output
        if let outPath = outputFile {
            do {
                try output.write(toFile: outPath, atomically: true, encoding: .utf8)
                printToStderr("[INFO] Dump written to \(outPath)")
            } catch {
                printToStderr("[ERROR] Failed to write to \(outPath): \(error)")
                exit(1)
            }
        } else {
            print(output, terminator: "")
        }
    }

    // MARK: - Argument parsing

    private static func parseOPJDumpArguments(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0

        let bareFlags: Set<String> = ["h", "help", "v"]
        let longOptions: [String: String] = [
            "ImgDir": "ImgDir",
        ]

        while i < args.count {
            let arg = args[i]

            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if bareFlags.contains(key) {
                    result[key] = "true"
                    i += 1
                } else if i + 1 < args.count {
                    result[key] = args[i + 1]
                    i += 2
                } else {
                    result[key] = "true"
                    i += 1
                }
            } else if arg.hasPrefix("-") {
                let key = String(arg.dropFirst(1))

                if bareFlags.contains(key) {
                    result[key] = "true"
                    i += 1
                } else if let mapped = longOptions[key] {
                    if i + 1 < args.count {
                        result[mapped] = args[i + 1]
                        i += 2
                    } else {
                        result[mapped] = "true"
                        i += 1
                    }
                } else if key.count == 1 {
                    if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                        result[key] = args[i + 1]
                        i += 2
                    } else {
                        result[key] = "true"
                        i += 1
                    }
                } else {
                    if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                        result[key] = args[i + 1]
                        i += 2
                    } else {
                        result[key] = "true"
                        i += 1
                    }
                }
            } else {
                i += 1
            }
        }

        return result
    }

    // MARK: - Help

    private static func printOPJDumpHelp() {
        print("""
        j2k dump - Dump JPEG 2000 codestream info (OpenJPEG-compatible)

        This command uses the same flags as OpenJPEG's opj_dump, so users
        familiar with OpenJPEG can use J2KSwift as a drop-in replacement.

        It dumps JPEG 2000 codestream info to stdout or a given file.

        Parameters:
        -----------

          -i <compressed file>
              REQUIRED only if an Input image directory is not specified.
              Currently accepts J2K-files, JP2-files, JPT-files, JPH-files,
              and JHC-files. The file type is identified based on its suffix.

          -o <output file>
              OPTIONAL
              Output file where file info will be dumped.
              By default it will be in stdout.

          -v
              OPTIONAL
              Enable informative messages.
              By default verbose mode is off.

          -ImgDir <directory>
              Image file Directory path.

          -h
              Display this help information.

        Examples:
        ---------

          j2k dump -i image.j2k
          j2k dump -i image.jp2 -o info.txt
          j2k dump -i image.jph -v
        """)
    }
}
