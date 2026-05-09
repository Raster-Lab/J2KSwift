// v8 Phase 6.2 — gated to macOS: invokes external CLIs via Process() (unavailable on iOS).
#if os(macOS)
// CrossCodecTooling.swift
// v5.38 lossless-only — shared helpers for cross-codec validation
// against external reference codecs (OpenJPEG, OpenJPH, Grok, Kakadu).
//
// Replaces the duplicated `runDecoder` patterns and hard-coded
// `/opt/homebrew/bin/...` paths scattered across J2KStrictCrossCodec
// ValidationTests, J2KMultiLayerEncodeTests, and the various HT
// cross-codec test files.
//
// SCOPE: lossless-focus only. None of these helpers are tied to
// `.constantBitrateStrict`, R-D selection, or Qstep search; they
// drive raw external compressors / expanders and read/write PGM
// 16-bit big-endian (the medical-corpus fixture format).

import Foundation
import XCTest
@testable import J2KCore
@testable import J2KCodec

enum CrossCodecTooling {

    /// External lossless reference codecs that the lossless gate
    /// expects to find on the test machine. Each entry knows its
    /// search paths and the binary names for compress + decompress.
    enum Codec: String, CaseIterable {
        case openjpeg, openjph, grok, kakadu

        /// Compressor binary name (the tool that ENCODES from a raw
        /// input — PGM/PPM/TIFF — into a J2K/JP2 codestream).
        var compressTool: String {
            switch self {
            case .openjpeg: return "opj_compress"
            case .openjph:  return "ojph_compress"
            case .grok:     return "grk_compress"
            case .kakadu:   return "kdu_compress"
            }
        }
        /// Decompressor binary name (J2K/JP2 → PGM/PPM/TIFF).
        var decompressTool: String {
            switch self {
            case .openjpeg: return "opj_decompress"
            case .openjph:  return "ojph_expand"
            case .grok:     return "grk_decompress"
            case .kakadu:   return "kdu_expand"
            }
        }
    }

    /// Default search paths, in priority order. Homebrew first
    /// (`/opt/homebrew/bin` on Apple Silicon), then the kakadu demo
    /// path, then the legacy Intel-Homebrew location.
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    /// Returns the first existing executable named `tool` in
    /// `searchPaths`, or nil if not present anywhere. Tests should
    /// `XCTSkip` when a needed tool is missing rather than fail.
    static func findTool(_ tool: String) -> URL? {
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: "\(dir)/\(tool)")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Runs `tool` with the given args. Captures stdout+stderr (so
    /// noisy tools don't pollute the test output). Returns the
    /// `terminationStatus` (0 == success). Throws on launch failure.
    @discardableResult
    static func runTool(_ tool: URL, args: [String]) throws -> Int32 {
        let proc = Process()
        proc.executableURL = tool
        proc.arguments = args
        proc.standardError = Pipe()
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }

    /// Runs `tool` with the given args and returns
    /// (terminationStatus, wallTimeMs). Same redirection as `runTool`.
    /// Wall time includes process start-up — that's fair, since this
    /// is what production users would observe when shelling out to
    /// the external codec.
    static func timeTool(_ tool: URL, args: [String]) throws -> (status: Int32, ms: Double) {
        let proc = Process()
        proc.executableURL = tool
        proc.arguments = args
        proc.standardError = Pipe()
        proc.standardOutput = Pipe()
        let start = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        return (proc.terminationStatus, ms)
    }

    // MARK: - Lossless mode selection

    /// Lossless codestream-format selection for the cross-codec gate.
    ///
    /// Two JPEG 2000 lossless flavours interoperate but produce
    /// different byte counts on the same input: classic Part 1 EBCOT
    /// (denser on high-bit-depth medical content, ~13-15% smaller
    /// than HT) and Part 15 HT cleanup-only (faster encode/decode,
    /// looser bytes). The default-mode invocations vary across the
    /// installed codecs:
    /// - J2KSwift: HT default
    /// - OpenJPH:  HT only (no EBCOT support — capability limit)
    /// - OpenJPEG: EBCOT default; CLI in this build cannot encode HT
    ///             (the `-M 64` HT bit emits an EBCOT codestream that
    ///             OpenJPH refuses with "Rsiz bit 14 is not set —
    ///             this is not a JPH file"; HT encoding requires a
    ///             different OpenJPEG build configuration)
    /// - Grok:     EBCOT default; HT requires `.jph` extension + `-M 64`
    /// - Kakadu:   EBCOT default; HT requires `Cmodes=HT`
    ///
    /// Pass `.htLossless` or `.ebcotLossless` to compare the same
    /// format across codecs (format-fair); pass `.defaultLossless`
    /// for the as-shipped codec defaults (mixed format).
    public enum LosslessMode {
        case defaultLossless
        case htLossless
        case ebcotLossless
    }

    /// Whether a codec supports a given mode through its installed
    /// CLI on this machine (probed against macOS Homebrew 2026-05-05).
    /// Returning `false` means the cross-codec gate should mark the
    /// cell as N/A rather than fake a result.
    static func codecSupports(_ codec: Codec, mode: LosslessMode) -> Bool {
        switch (codec, mode) {
        case (.openjpeg, .htLossless): return false  // CLI build limit
        case (.openjph,  .ebcotLossless): return false  // HT-only codec
        default: return true
        }
    }

    // MARK: - Codec-specific lossless invocations
    //
    // Below we centralise the canonical lossless invocation for each
    // codec across the three modes, verified against the installed
    // binaries on 2026-05-05:
    //
    //   - opj_compress  v2.5.4  default = EBCOT; HT not exposed via CLI
    //   - ojph_compress         HT-only;          EBCOT N/A
    //   - grk_compress          default = EBCOT; HT via .jph + -M 64
    //   - kdu_compress  v8.4.1  default = EBCOT; HT via Cmodes=HT
    //
    // The output extension is fixed per codec: `.j2k` for EBCOT and
    // OpenJPEG/Kakadu HT, `.jph` for Grok HT (Grok requires the
    // jph extension to honour the `-M 64` mode flag — a `.j2k` HT
    // request errors with "High throughput compression mode cannot
    // be used for non-HTJ2K file"). Callers must pass the matching
    // extension via `output`.

    /// Runs the lossless compressor for `codec` on `input` (a PGM
    /// path) and writes a J2K (or .jph) codestream to `output`.
    /// Returns (status, ms). Returns (-1, 0) if the tool isn't
    /// installed; returns (-2, 0) if the requested mode isn't
    /// supported by this codec's installed CLI.
    static func compressLossless(
        _ codec: Codec,
        mode: LosslessMode,
        input: String,
        output: String
    ) throws -> (status: Int32, ms: Double) {
        guard codecSupports(codec, mode: mode) else { return (-2, 0.0) }
        guard let tool = findTool(codec.compressTool) else {
            return (-1, 0.0)
        }
        let args: [String]
        switch (codec, mode) {
        // --- defaults ---
        case (.openjpeg, .defaultLossless), (.openjpeg, .ebcotLossless):
            args = ["-i", input, "-o", output]
        case (.openjph, .defaultLossless), (.openjph, .htLossless):
            args = ["-i", input, "-o", output, "-reversible", "true"]
        case (.grok, .defaultLossless), (.grok, .ebcotLossless):
            args = ["-i", input, "-o", output]
        case (.kakadu, .defaultLossless), (.kakadu, .ebcotLossless):
            args = ["-i", input, "-o", output, "Creversible=yes", "-quiet"]

        // --- explicit HT (where supported by CLI) ---
        case (.grok, .htLossless):
            // Grok requires the `.jph` extension to accept `-M 64`.
            // The caller is expected to pass an output ending in `.jph`.
            args = ["-i", input, "-o", output, "-M", "64"]
        case (.kakadu, .htLossless):
            args = ["-i", input, "-o", output, "Creversible=yes", "Cmodes=HT", "-quiet"]

        // --- unreachable per `codecSupports` guard above ---
        case (.openjpeg, .htLossless),
             (.openjph, .ebcotLossless):
            return (-2, 0.0)
        }
        return try timeTool(tool, args: args)
    }

    /// Runs the decompressor for `codec` on `input` (J2K or .jph
    /// codestream) and writes a PGM to `output`. Returns (status, ms).
    /// Decompressors don't need a mode parameter — they auto-detect
    /// the format from the codestream header.
    static func decompressLossless(_ codec: Codec, input: String, output: String) throws -> (status: Int32, ms: Double) {
        guard let tool = findTool(codec.decompressTool) else {
            return (-1, 0.0)
        }
        let args: [String]
        switch codec {
        case .openjpeg:
            args = ["-i", input, "-o", output]
        case .openjph:
            args = ["-i", input, "-o", output]
        case .grok:
            args = ["-i", input, "-o", output]
        case .kakadu:
            args = ["-i", input, "-o", output, "-quiet"]
        }
        return try timeTool(tool, args: args)
    }

    /// File extension a given codec needs for its compressed output
    /// in a given mode. Most cases use `.j2k`; Grok HT mode requires
    /// `.jph`.
    static func compressedExtension(_ codec: Codec, mode: LosslessMode) -> String {
        switch (codec, mode) {
        case (.grok, .htLossless): return ".jph"
        default: return ".j2k"
        }
    }

    /// Returns the file size of `path`, or 0 if missing. Convenience
    /// for tests reporting the codestream byte size.
    static func fileSize(_ path: String) -> Int {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: path),
              let n = attr[.size] as? Int else { return 0 }
        return n
    }

    // MARK: - Medical corpus fixture index

    /// One row of the medical-corpus fixture index.
    struct MedicalFixture {
        let modality: String   // CT, MR, MR-small, XA, PX, DX, MG
        let path: String       // filename relative to Tests/Fixtures/CrossCodec/
        let labelHint: String  // human-readable shape, populated post-load if present
    }

    /// The lossless gate runs every fixture present on disk; missing
    /// fixtures `XCTSkip` rather than fail (so the gate is still
    /// useful in CI environments without the full corpus).
    static let medicalCorpus: [MedicalFixture] = [
        .init(modality: "MR-small", path: "mr_study_002_instance_000100.pgm", labelHint: "180×180"),
        .init(modality: "CT",       path: "ct_study_001_instance_000001.pgm", labelHint: "512×512"),
        .init(modality: "CT",       path: "ct_study_003_instance_000050.pgm", labelHint: "512×512"),
        .init(modality: "MR",       path: "mr_study_001_instance_000001.pgm", labelHint: "886×886"),
        .init(modality: "XA",       path: "xa_study_001_instance_000001.pgm", labelHint: "1024×1024"),
        .init(modality: "PX",       path: "px_study_001_instance_000001.pgm", labelHint: "2459×1316"),
        .init(modality: "DX",       path: "dx_study_002_instance_000001.pgm", labelHint: "2800×2288"),
    ]

    /// Resolves a fixture filename to its absolute path under
    /// `Tests/Fixtures/CrossCodec/`. Returns nil if the file is
    /// missing on disk.
    static func fixtureURL(_ filename: String, file: StaticString = #filePath) -> URL? {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let packageRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidate = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/\(filename)")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    // MARK: - PGM 16-bit big-endian I/O

    /// Loads a P5 PGM 16-bit big-endian file into a J2KImage. The
    /// medical-corpus fixtures all share this format. Returns nil
    /// when the file is missing.
    static func loadPGM16BE(_ url: URL) throws -> J2KImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        // Header: P5 width height maxval, with arbitrary whitespace and
        // optional `#` comment lines.
        var i = 2  // skip "P5"
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 {  // '#'
                while i < data.count, data[i] != 0x0A { i += 1 }
                continue
            }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30)
                i += 1
            }
            fields.append(num)
        }
        if i < data.count, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        let payload = data.subdata(in: i..<data.count)
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0,
                bitDepth: fields[2] > 255 ? 16 : 8,
                signed: false,
                width: fields[0], height: fields[1],
                data: payload,
                sampleByteOrder: .bigEndian)])
    }

    /// Returns true iff the two J2KImages have identical pixel data
    /// (component-wise, byte-wise). Used to assert exact-reconstruction
    /// in lossless tests. The comparison is byte-exact on the raw
    /// component data, so it's sensitive to bit-depth / signedness /
    /// endianness mismatches — which is what we want.
    static func bitExactPixelMatch(_ lhs: J2KImage, _ rhs: J2KImage) -> Bool {
        guard lhs.width == rhs.width,
              lhs.height == rhs.height,
              lhs.components.count == rhs.components.count
        else { return false }
        for (a, b) in zip(lhs.components, rhs.components) {
            if a.bitDepth != b.bitDepth { return false }
            if a.signed != b.signed { return false }
            if a.data != b.data { return false }
        }
        return true
    }

    /// Returns the maximum absolute pixel difference between two
    /// J2KImages, treating each component sample as the bit-depth
    /// integer it represents. 0 means bit-exact. Useful diagnostic
    /// when `bitExactPixelMatch` returns false — tells you whether
    /// the divergence is single-LSB rounding or catastrophic.
    static func maxAbsPixelDiff(_ lhs: J2KImage, _ rhs: J2KImage) -> Int {
        guard lhs.width == rhs.width,
              lhs.height == rhs.height,
              lhs.components.count == rhs.components.count
        else { return Int.max }
        var maxDiff = 0
        for (a, b) in zip(lhs.components, rhs.components) {
            let bytesPerSample = (a.bitDepth + 7) / 8
            guard a.data.count == b.data.count,
                  a.data.count % bytesPerSample == 0 else {
                return Int.max
            }
            a.data.withUnsafeBytes { aBuf in
                b.data.withUnsafeBytes { bBuf in
                    let n = a.data.count / bytesPerSample
                    for s in 0..<n {
                        var av = 0, bv = 0
                        if bytesPerSample == 2 {
                            // big-endian convention used by the corpus
                            let off = s * 2
                            av = (Int(aBuf[off]) << 8) | Int(aBuf[off + 1])
                            bv = (Int(bBuf[off]) << 8) | Int(bBuf[off + 1])
                        } else {
                            av = Int(aBuf[s])
                            bv = Int(bBuf[s])
                        }
                        let d = abs(av - bv)
                        if d > maxDiff { maxDiff = d }
                    }
                }
            }
        }
        return maxDiff
    }
}

#endif // os(macOS)
