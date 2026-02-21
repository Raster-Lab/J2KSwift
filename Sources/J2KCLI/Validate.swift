//
// Validate.swift
// J2KSwift
//
/// Validate command – check JPEG 2000 codestream conformance

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    /// Validate command: check a JPEG 2000 file for conformance.
    static func validateCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printValidateHelp()
            return
        }

        guard let filePath = options["_positional"] ?? options["i"] ?? options["input"] else {
            print("Error: Missing file argument")
            print("Usage: j2k validate <file> [options]")
            exit(1)
        }

        let checkPart1  = options["part1"]  != nil
        let checkPart2  = options["part2"]  != nil
        let checkPart15 = options["part15"] != nil
        let strict      = options["strict"] != nil
        let jsonOutput  = options["json"]   != nil
        let quiet       = options["quiet"]  != nil

        // Load file
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        } catch {
            if jsonOutput {
                printJSON(["valid": false, "file": filePath, "error": error.localizedDescription])
            } else if !quiet {
                print("Error: Cannot read file '\(filePath)': \(error.localizedDescription)")
            }
            exit(1)
        }

        let containerFormat = detectContainerFormat(data)
        let codestream      = extractCodestream(from: data, format: containerFormat)

        var issues:   [String] = []
        var warnings: [String] = []

        // --- Basic SOC check ---
        let socResult = J2KMarkerSegmentValidator.validateSOC(codestream)
        if !socResult.isCompliant {
            for i in socResult.issues { issues.append(i.message) }
        }

        // --- Codestream syntax ---
        let syntaxResult = J2KCodestreamSyntaxValidator.validateMarkerOrdering(codestream)
        issues.append(contentsOf: syntaxResult.errors)
        if strict { warnings.append(contentsOf: syntaxResult.warnings) }

        // --- Full codestream marker validation ---
        let csResult = J2KMarkerSegmentValidator.validateCodestream(codestream)
        if !csResult.isCompliant {
            for i in csResult.issues { issues.append(i.message) }
        }

        // --- Part 1 conformance ---
        if checkPart1 || (!checkPart2 && !checkPart15) {
            // Decode attempt is the primary Part 1 check
            let decoder = J2KDecoder()
            do {
                _ = try decoder.decode(codestream)
            } catch {
                issues.append("Part 1 decode failed: \(error.localizedDescription)")
            }
        }

        // --- Part 15 (HTJ2K) check ---
        if checkPart15 {
            let isHT = detectHTJ2K(codestream)
            if !isHT {
                issues.append("Part 15: No HTJ2K CAP marker found – does not appear to be HTJ2K")
            }
        }

        let valid = issues.isEmpty

        if jsonOutput {
            var result: [String: Any] = [
                "file":     filePath,
                "format":   containerFormat,
                "valid":    valid,
                "issues":   issues,
                "warnings": warnings,
            ]
            result["part1Checked"]  = checkPart1
            result["part2Checked"]  = checkPart2
            result["part15Checked"] = checkPart15
            printJSON(result)
        } else if !quiet {
            if valid {
                print("VALID: \(filePath)")
            } else {
                print("INVALID: \(filePath)")
                for issue in issues {
                    print("  ✗ \(issue)")
                }
            }
            if !warnings.isEmpty {
                print("Warnings:")
                for w in warnings { print("  ⚠ \(w)") }
            }
        }

        exit(valid ? 0 : 1)
    }

    // MARK: - Help

    private static func printValidateHelp() {
        print("""
        j2k validate - Validate a JPEG 2000 codestream

        USAGE:
            j2k validate <file> [options]

        OPTIONS:
            --part1     Check Part 1 conformance
            --part2     Check Part 2 conformance
            --part15    Check Part 15 (HTJ2K) conformance
            --strict    Strict mode (also report warnings)
            --json      Output results as JSON
            --quiet     Suppress non-error output

        EXIT CODES:
            0   File is valid
            1   File is invalid or an error occurred
        """)
    }
}
