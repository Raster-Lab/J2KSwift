//
// Commands.swift
// J2KSwift
//
/// Command implementations for J2KCLI

import Foundation
import J2KCore
import J2KCodec
#if os(macOS)
import J2KDaemonClient
#endif

extension J2KCLI {
    /// Parse command-line arguments into a dictionary.
    ///
    /// Normalises British/American spelling variants so callers only need to check
    /// the canonical (American) form.  Positional arguments are stored under the
    /// synthetic key `"_positional"`.
    static func parseArguments(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0

        while i < args.count {
            let arg = args[i]

            if arg.hasPrefix("--") {
                let raw = String(arg.dropFirst(2))
                let key = Self.normaliseKey(raw)
                if i + 1 < args.count && Self.isOptionValue(args[i + 1]) {
                    result[key] = args[i + 1]
                    i += 2
                } else {
                    result[key] = "true"
                    i += 1
                }
            } else if arg.hasPrefix("-") && arg.count == 2 {
                let key = String(arg.dropFirst())
                if i + 1 < args.count && Self.isOptionValue(args[i + 1]) {
                    result[key] = args[i + 1]
                    i += 2
                } else {
                    result[key] = "true"
                    i += 1
                }
            } else {
                // Treat unrecognised bare tokens as positional arguments
                result["_positional"] = arg
                i += 1
            }
        }

        return result
    }

    /// A token is a value for the preceding option unless it looks like a flag.
    /// A bare `-` is the stdin/stdout pipe sentinel (`-i -`, `-o -`), not a flag.
    static func isOptionValue(_ token: String) -> Bool {
        token == "-" || !token.hasPrefix("-")
    }

    /// Normalise a flag key so that British and American spellings map to the same key.
    static func normaliseKey(_ key: String) -> String {
        switch key {
        // --colour -> --color
        case "colour":                  return "color"
        case "colour-space":            return "color-space"
        case "no-colour":               return "no-color"
        // --optimise -> --optimize
        case "optimise":                return "optimize"
        case "optimise-progressive":    return "optimize-progressive"
        // --normalise -> --normalize
        case "normalise":               return "normalize"
        default:                        return key
        }
    }

    /// Encode command: convert image to JPEG 2000
    static func encodeCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printEncodeHelp()
            return
        }

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        let pipeInput  = (inputPath == "-")
        let pipeOutput: Bool
        let outputPath: String

        if let o = options["o"] ?? options["output"] {
            pipeOutput = (o == "-")
            outputPath = o
        } else {
            pipeOutput = false
            outputPath = deriveOutputPath(inputPath: inputPath, command: "encode", options: options)
        }

        let showTiming  = options["timing"] != nil
        let jsonOutput  = options["json"] != nil
        let verbose     = options["verbose"] != nil
        let quiet       = options["quiet"] != nil

        // Load input image
        if verbose { printInfo("Loading: \(inputPath)", pipeMode: pipeOutput) }
        let startLoad = Date()
        let image: J2KImage
        if pipeInput {
            image = try await loadImageFromStdin()
        } else {
            image = try loadImage(from: inputPath)
        }
        let loadTime = Date().timeIntervalSince(startLoad)
        if verbose { printInfo("  \(image.width)×\(image.height), \(image.componentCount) component(s)", pipeMode: pipeOutput) }

        // Configure encoder
        var config: J2KEncodingConfiguration

        if let preset = options["preset"] {
            switch preset {
            case "fast":     config = J2KEncodingPreset.fast.configuration()
            case "balanced": config = J2KEncodingPreset.balanced.configuration()
            case "quality":  config = J2KEncodingPreset.quality.configuration()
            default:
                print("Error: Unknown preset '\(preset)'")
                exit(1)
            }
        } else {
            config = J2KEncodingConfiguration()
        }

        // Quality / rate modes
        // Default to lossless when no lossy options are specified (matches OpenJPEG)
        if options["lossless"] != nil {
            config.lossless = true
        } else if let qstepStr = options["qstep"], let qstep = Double(qstepStr) {
            // v5.18.0: fixed-qstep mode (OpenJPH-style). Bypasses
            // PCRD-opt; every block included unchanged. Calibrated
            // qstep table for medical workflows lives in
            // Scripts/rd_benchmark.py:_ojph_qstep_for_target_bpp.
            config.bitrateMode = .fixedQstep(qstep: qstep)
            config.lossless = false
        } else if let viaQstepBpp = options["bitrate-via-qstep"], let bpp = Double(viaQstepBpp) {
            // v5.19.0: target-bpp via qstep search. Outer loop
            // iterates qstep until achieved bpp matches target within
            // tolerance. Combines .constantBitrate's convenience with
            // .fixedQstep's R-D quality. Slower (4–6 encode iters)
            // but closes the v5.16.0 R-D gap.
            config.bitrateMode = .constantBitrateViaQstep(bitsPerPixel: bpp)
            config.lossless = false
        } else if let bpStr = options["bitrate"], let bpp = Double(bpStr) {
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        } else if let qualStr = options["q"] ?? options["quality"],
                  let quality = Double(qualStr) {
            config.quality = quality
        } else if options["irreversible"] == nil && options["visually-lossless"] == nil {
            // No lossy option specified — default to lossless
            config.lossless = true
        }

        if options["visually-lossless"] != nil {
            config.quality = 0.99
        }

        // Filter selection: --irreversible forces 9/7 DWT, --reversible forces 5/3
        if options["irreversible"] != nil {
            config.useReversibleFilter = false
        } else if options["reversible"] != nil {
            config.useReversibleFilter = true
        }

        // Structural options
        if let levelsStr = options["levels"], let levels = Int(levelsStr) {
            config.decompositionLevels = levels
        }
        if let layersStr = options["layers"], let layers = Int(layersStr) {
            config.qualityLayers = layers
        }
        if let blocksizeStr = options["blocksize"] {
            let parts = blocksizeStr.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { config.codeBlockSize = (parts[0], parts[1]) }
        }
        if let tileSizeStr = options["tile-size"] {
            let parts = tileSizeStr.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { config.tileSize = (parts[0], parts[1]) }
        }
        if let progStr = options["progression"] {
            if let order = J2KProgressionOrder(rawValue: progStr.uppercased()) {
                config.progressionOrder = order
            } else {
                print("Error: Unknown progression order '\(progStr)'. Expected: LRCP, RLCP, RPCL, PCRL, CPRL")
                exit(1)
            }
        }
        if options["htj2k"] != nil {
            config.useHTJ2K = true
            // Default --htj2k to spec-conformant Part-15 codeblocks so the
            // output interops with OpenJPH and other Part-15 decoders out
            // of the box. The J2KSwift-private `.custom` block format is
            // smaller in some configurations but only J2KSwift can decode
            // it; users who need the legacy format can opt in with
            // --htj2k-custom.
            config.htj2kBlockFormat = .conformant
        }
        if options["htj2k-custom"] != nil {
            // Explicit opt-in to the J2KSwift-private custom block format.
            // Implies --htj2k. Useful for archives generated by older
            // J2KSwift versions or for research where smaller-but-private
            // codestreams are acceptable.
            config.useHTJ2K = true
            config.htj2kBlockFormat = .custom
        }
        if options["no-mct"] != nil { config.mctConfiguration = .disabled }

        // Codec variant selection
        if let codec = options["codec"] {
            applyCodecOption(codec, to: &config)
        }

        // Compression ratio / percentage
        if let ratioStr = options["compression-ratio"] {
            // Parse "N:1" format
            let parts = ratioStr.split(separator: ":")
            if let ratio = parts.first.flatMap({ Double($0) }) {
                let bpp = Double(image.componentCount * image.components[0].bitDepth) / ratio
                config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
            }
        }
        if let pctStr = options["compression-percent"], let pct = Double(pctStr) {
            // N% size reduction => ratio = 100 / (100 - N)
            let ratio = 100.0 / max(1, 100.0 - pct)
            let bpp = Double(image.componentCount * image.components[0].bitDepth) / ratio
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }
        if let sizeStr = options["target-size"], let targetBytes = Int(sizeStr) {
            let totalPixels = image.width * image.height
            let bpp = Double(targetBytes * 8) / Double(totalPixels)
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }

        // Note: enabling MCT via --mct uses the default configuration from preset
        // GPU toggle is noted but has no effect on this platform
        if verbose, options["gpu"] != nil { print("Note: GPU acceleration requested (not available on this platform)") }

        // Encode
        if verbose { print("Encoding…") }
        let encoder = J2KEncoder(encodingConfiguration: config)
        let startEncode = Date()

        // v8.8 (research): encoder daemon routing — symmetric to decode.
        // The default config (HT-conformant lossless 5/3) is the only
        // shape the daemon currently accepts. For other configs (e.g.
        // legacy JPEG 2000 Part 1, JP2 wrapping, custom decomposition
        // levels), fall back to in-process to preserve behavior.
        let encodeDaemonValue = options["daemon"]
        let encodeNoDaemonExplicit = options["no-daemon"] != nil
        // Threshold for --daemon=auto: ENCODE is dominated by per-process
        // codec library load (HT block coders, MCT tables, DWT scratch
        // pools, ~30 ms on cold-cache). The daemon amortises that across
        // calls, so the encoder daemon wins for ALL fixture sizes — even
        // a 512×512 fixture goes 41 ms in-proc → 13 ms daemon. The
        // decode threshold (3 MP) does NOT apply to encode. Drop to 0
        // so `--daemon=auto` for encode is effectively the same as
        // `--daemon` (always-on, with fallback to in-process if daemon
        // unreachable).
        let useEncodeDaemon: Bool
        if let v = encodeDaemonValue, !encodeNoDaemonExplicit {
            if v.lowercased() == "auto" {
                // Auto: always use daemon for encode (library-load
                // amortisation always wins). Fallback to in-process
                // happens transparently if daemon is unreachable.
                useEncodeDaemon = true
            } else {
                useEncodeDaemon = true
            }
        } else {
            useEncodeDaemon = false
        }

        let isDefaultLosslessHT = config.lossless && config.useHTJ2K
            && config.useReversibleFilter
            && (config.htj2kBlockFormat == .conformant)
            && config.decompositionLevels == 5
            && image.componentCount == 1

        var encodedData: Data
        var usedEncodeDaemon = false
        #if os(macOS)
        if useEncodeDaemon && isDefaultLosslessHT && !pipeInput,
           let comp0 = image.components.first {
            let client = J2KDaemonClient()
            do {
                encodedData = try await client.encode(
                    pixelData: comp0.data,
                    width: image.width, height: image.height,
                    bitDepth: comp0.bitDepth, signed: comp0.signed)
                usedEncodeDaemon = true
                await client.close()
            } catch {
                if verbose {
                    printInfo("(encode daemon unavailable, encoding in-process)", pipeMode: pipeOutput)
                }
                await client.close()
                encodedData = try await encoder.encode(image)
            }
        } else {
            encodedData = try await encoder.encode(image)
        }
        #else
        encodedData = try await encoder.encode(image)
        #endif
        let encodeTime = Date().timeIntervalSince(startEncode)
        if verbose && usedEncodeDaemon {
            printInfo("(encoded via daemon at warm-process speed)", pipeMode: pipeOutput)
        }

        // Wrap in JP2 container if requested
        let format = options["format"] ?? "j2k"
        if format == "jp2" || format == "jpx" {
            encodedData = wrapInJP2Container(encodedData, image: image)
        }

        // Progress indicator for verbose mode
        if verbose { printInfo("Writing: \(outputPath)", pipeMode: pipeOutput) }

        // Write output
        let startWrite = Date()
        if pipeOutput {
            FileHandle.standardOutput.write(encodedData)
        } else {
            try encodedData.write(to: URL(fileURLWithPath: outputPath))
        }
        let writeTime = Date().timeIntervalSince(startWrite)

        // Output results
        let inputBytes = image.width * image.height * image.componentCount
        let compressionRatio = Double(inputBytes) / Double(encodedData.count)

        if jsonOutput {
            let result: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "format": format,
                "inputSize": inputBytes,
                "outputSize": encodedData.count,
                "compressionRatio": compressionRatio,
                "width": image.width,
                "height": image.height,
                "components": image.componentCount,
                "timing": [
                    "load": loadTime,
                    "encode": encodeTime,
                    "write": writeTime,
                    "total": loadTime + encodeTime + writeTime
                ]
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                printInfo(jsonString, pipeMode: pipeOutput)
            }
        } else if !quiet {
            printInfo("Encoded: \(inputPath) -> \(outputPath)", pipeMode: pipeOutput)
            printInfo("  Input:  \(image.width)×\(image.height), \(image.componentCount) component(s)", pipeMode: pipeOutput)
            printInfo("  Output size: \(formatBytes(encodedData.count))", pipeMode: pipeOutput)
            printInfo("  Compression ratio: \(String(format: "%.2f", compressionRatio)):1", pipeMode: pipeOutput)
            if showTiming {
                printInfo("  Timing:", pipeMode: pipeOutput)
                printInfo("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Encode: \(String(format: "%7.3f", encodeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Total:  \(String(format: "%7.3f", (loadTime + encodeTime + writeTime) * 1000)) ms", pipeMode: pipeOutput)
            }
        }
    }

    private static func printEncodeHelp() {
        print("""
        j2k encode - Encode an image to JPEG 2000

        USAGE:
            j2k encode -i <input> [-o <output>] [options]

        OPTIONS:
            -i, --input PATH            Input image (PGM, PPM, TIFF, PNG, DICOM)
            -o, --output PATH           Output file (optional; derived from input name if omitted)
            -q, --quality FLOAT         Quality 0.0-1.0 (default 1.0)
            --lossless                  Lossless compression
            --bitrate BPP               Target bit-rate (bits per pixel)
            --bitrate-via-qstep BPP     Target bpp via qstep search (better R-D, ~5× slower)
            --qstep STEP                Fixed quantization step (OpenJPH-style; lossy 9/7 only)
            --psnr VALUE                Target PSNR (dB)
            --visually-lossless         Near-lossless preset
            --reversible                Use 5/3 reversible DWT (default, best for medical)
            --irreversible              Use 9/7 irreversible DWT
            --preset fast|balanced|quality  Encoding preset
            --levels N                  DWT decomposition levels
            --blocksize WxH             Code-block size (e.g. 64x64)
            --layers N                  Quality layers
            --format j2k|jp2|jpx        Output container format
            --progression ORDER         LRCP|RLCP|RPCL|PCRL|CPRL
            --tile-size WxH             Tile size
            --htj2k                     Use HTJ2K (Part 15) — emits spec-conformant blocks
            --htj2k-custom              HTJ2K with J2KSwift-private block format (legacy)
            --mct / --no-mct            Multi-component transform
            --gpu / --no-gpu            GPU acceleration
            --colour-space CS           Set colour space
            --verbose                   Verbose output
            --quiet                     Suppress output
            --timing                    Show timing breakdown
            --json                      JSON output

        PIPING:
            -i -                        Read input from stdin
            -o -                        Write output to stdout
            When piping, diagnostic messages are sent to stderr.

        EXAMPLES:
            j2k encode -i input.pgm -o output.j2k --lossless
            j2k encode -i input.tiff --htj2k
            j2k encode -i scan.dcm -o compressed.jp2 --format jp2
            cat image.pgm | j2k encode -i - -o output.j2k
        """)
    }

    /// Decode command: convert JPEG 2000 to image
    static func decodeCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printDecodeHelp()
            return
        }

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        let pipeInput  = (inputPath == "-")
        let explicitOutput = options["o"] ?? options["output"]
        let pipeOutput = (explicitOutput == "-")

        let showTiming = options["timing"] != nil
        let jsonOutput = options["json"] != nil
        let verbose    = options["verbose"] != nil
        let quiet      = options["quiet"] != nil

        // Partial-decoding options — wired to the v10.4–v10.7 partial-decode
        // APIs: `--level` → decodeResolution (entropy-skip + truncated iDWT,
        // 3-8× thumbnail speedup), `--region` → decodeRegion(.direct)
        // (code-block footprint filter + tile-granular skip).
        let resolutionLevel = options["level"].flatMap { Int($0) }
        let qualityLayer    = options["layer"].flatMap { Int($0) }
        let region: J2KRegion?
        if let regionStr = options["region"] {
            guard let parsed = parseRegion(regionStr) else {
                print("Error: --region expects x,y,width,height (e.g. --region 0,0,512,512)")
                exit(1)
            }
            region = parsed
        } else {
            region = nil
        }
        let componentFilter: [Int]? = {
            if let single = options["component"].flatMap({ Int($0) }) { return [single] }
            if let list = options["components"] {
                let parsed = list.split(separator: ",").compactMap { Int($0) }
                return parsed.isEmpty ? nil : parsed
            }
            return nil
        }()
        let headerOnly      = options["header-only"] != nil
        let stripAlpha      = options["strip-alpha"] != nil
        let scale           = options["scale"].flatMap { Int($0) }
        let outputFormat    = options["output-format"]
        let bitDepthConvert = options["bit-depth"].flatMap { Int($0) }
        // Opt-in GPU HTJ2K entropy decode (M2-prime, v5.5.0+). When the
        // codestream is HTJ2K conformant cleanup-only AND Metal is
        // available, eligible codeblocks are batched through the GPU
        // HT cleanup kernel. Ineligible blocks fall back to CPU
        // automatically. Inert on Part 1 codestreams. Implies GPU
        // inverse DWT (uses J2KDecoder.decodeWithGPUHT internally).
        let useGPUHT        = options["gpu-ht"] != nil
        // v8 Phase 2 — CLI defaults to CPU-first routing for single-
        // shot invocations. Phase 1 (#381) localised that the GPU
        // paths' 50 ms Metal cold-start tax dominates one-shot CLI
        // walls — measured 52-53 ms slower than --no-gpu on every
        // CT/MR/DX fixture in default mode. Users running batches
        // through a long-lived process don't pay this on every
        // invocation; CLI users do. The Metal-first v8 strategy
        // says "Metal becomes the default WHERE IT'S FASTER" — for
        // CLI single-shot it isn't, so the CLI default flips to
        // CPU. Users who explicitly want the GPU paths can pass
        // `--gpu` (or `--gpu-ht` for HT GPU entropy decode); both
        // override this default.
        let explicitGPU = (options["gpu"] != nil && options["gpu"] != "false")
                       || (options["gpu-ht"] != nil)
        let forceCPU = options["no-gpu"] != nil || !explicitGPU
        if forceCPU {
            setenv("J2K_GPU_INVERSE_53", "0", 1)
            // Note: GPU HT entropy decode defaults OFF since v10.3.0, so no
            // env override is needed here (the previously-set
            // `J2K_GPU_HT_ENTROPY` was a dead variable — the pipeline reads
            // `J2K_GPU_HT_ENTROPY_DECODE`).
        }
        _ = (stripAlpha, scale, outputFormat, bitDepthConvert)

        if verbose {
            printInfo("Loading: \(inputPath)", pipeMode: pipeOutput)
            if let l = resolutionLevel { printInfo("  Resolution level: \(l)", pipeMode: pipeOutput) }
            if let l = qualityLayer    { printInfo("  Quality layer: \(l)", pipeMode: pipeOutput) }
            if let r = region {
                printInfo("  Region: \(r.x),\(r.y) \(r.width)×\(r.height)", pipeMode: pipeOutput)
            }
        }

        // Load encoded data
        // v8.8 (research): use `.alwaysMapped` for file input — kernel mmap
        // gives near-zero load time and defers actual page-in to where the
        // decoder reads bytes. On cold-shot DX (12 MB codestream) this saves
        // ~1-3 ms vs `Data(contentsOf:)` which copies the file into anonymous
        // memory eagerly.
        let startLoad = Date()
        let encodedData: Data
        if pipeInput {
            encodedData = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            encodedData = try Data(contentsOf: URL(fileURLWithPath: inputPath),
                                   options: [.alwaysMapped])
        }
        let loadTime = Date().timeIntervalSince(startLoad)

        // Decode
        let decoder = J2KDecoder()
        let startDecode = Date()
        let decodedImage: J2KImage

        // v8.8 (research): default flipped — daemon is now OPT-IN via
        // `--daemon` instead of opt-out via `--no-daemon`.
        //
        // Reason: V8_8_VERIFICATION_REPORT measured a -20.98 ms regression
        // across the medical corpus on warm-cache CLI loops (small/medium
        // fixtures pay 5-7 ms NSXPCInterface proxy overhead each). The
        // daemon's only meaningful benefit is on TRULY cold-shot scenarios
        // (first invocation per session, no file cache, Metal not yet
        // initialised) — not the typical CLI loop case.
        //
        // - `--daemon`         opt-in: route via j2kd if reachable
        // - `--daemon auto`    research: route via j2kd ONLY when
        //                      codestream ≥ 3 MB (≈ 3 MP image), so the
        //                      daemon's decode time amortises NSXPC
        //                      proxy overhead (per V8_8_DAEMON_FIXTURE_SCALING.md)
        // - (no flag)          default: in-process decode (no proxy overhead)
        // - `--no-daemon`      preserved as explicit no-op alias for clarity +
        //                      backward-compat with anyone who scripted
        //                      around the v8.1.x default
        //
        // If the daemon is opt-in but unreachable, we transparently fall
        // back to in-process — the in-process path always works.
        let daemonValue = options["daemon"]
        let noDaemonExplicit = options["no-daemon"] != nil
        let useDaemon: Bool
        if let v = daemonValue {
            if v.lowercased() == "auto" {
                // Research-mode threshold: 3 MB codestream ≈ 3 MP at
                // typical lossless 5/3 ratios. Below this, daemon decode
                // is shorter than NSXPC machinery and the overhead is
                // exposed; above, decode time hides the proxy overhead.
                useDaemon = encodedData.count >= 3 * 1024 * 1024
            } else {
                // --daemon (true), --daemon yes, --daemon true, etc. → opt-in.
                useDaemon = true
            }
        } else {
            useDaemon = false
        }
        // Partial decode (--level / --region) is in-process only — the daemon
        // protocol has no partial-decode RPC.
        let partialRequested = (resolutionLevel != nil) || (region != nil)
        var usedDaemon = false
        #if os(macOS)
        if useDaemon && !noDaemonExplicit && !useGPUHT && !pipeInput && !partialRequested {
            let client = J2KDaemonClient()
            do {
                decodedImage = try await client.decode(encodedData)
                usedDaemon = true
                await client.close()
            } catch {
                if verbose {
                    printInfo("(daemon decode unavailable for this request — " +
                              "decoding in-process: \(error))", pipeMode: pipeOutput)
                }
                await client.close()
                decodedImage = try await decodeInProcess(
                    decoder, data: encodedData, level: resolutionLevel, region: region,
                    layer: qualityLayer, components: componentFilter, useGPUHT: useGPUHT)
            }
        } else {
            decodedImage = try await decodeInProcess(
                decoder, data: encodedData, level: resolutionLevel, region: region,
                layer: qualityLayer, components: componentFilter, useGPUHT: useGPUHT)
        }
        #else
        decodedImage = try await decodeInProcess(
            decoder, data: encodedData, level: resolutionLevel, region: region,
            layer: qualityLayer, components: componentFilter, useGPUHT: useGPUHT)
        #endif
        let decodeTime = Date().timeIntervalSince(startDecode)
        if verbose && usedDaemon {
            printInfo("(decoded via daemon at warm-process speed)", pipeMode: pipeOutput)
        }

        // Header-only mode: print info and exit
        if headerOnly {
            printInfo("Codestream Info:", pipeMode: pipeOutput)
            printInfo("  Dimensions: \(decodedImage.width)×\(decodedImage.height)", pipeMode: pipeOutput)
            printInfo("  Components: \(decodedImage.componentCount)", pipeMode: pipeOutput)
            for c in decodedImage.components {
                printInfo("  [\(c.index)] \(c.width)×\(c.height), \(c.bitDepth)-bit \(c.signed ? "signed" : "unsigned")", pipeMode: pipeOutput)
            }
            return
        }

        // Post-processing: bit depth conversion
        var image = decodedImage
        if let targetBD = bitDepthConvert {
            image = convertBitDepth(image, to: targetBD)
        }

        // Derive output path if not specified (after decoding, so component count is known)
        let outputPath: String
        if let o = explicitOutput {
            outputPath = o
        } else {
            outputPath = deriveOutputPath(inputPath: inputPath, command: "decode", options: options, componentCount: image.componentCount)
        }

        // Write output
        if verbose { printInfo("Writing: \(outputPath)", pipeMode: pipeOutput) }
        let startWrite = Date()
        if pipeOutput {
            try saveImageToStdout(image, format: outputFormat)
        } else {
            try saveImage(image, to: outputPath)
        }
        let writeTime = Date().timeIntervalSince(startWrite)

        // Output results
        if jsonOutput {
            let result: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "inputSize": encodedData.count,
                "width": image.width,
                "height": image.height,
                "components": image.componentCount,
                "resolutionLevel": resolutionLevel as Any,
                "qualityLayer": qualityLayer as Any,
                "timing": [
                    "load": loadTime,
                    "decode": decodeTime,
                    "write": writeTime,
                    "total": loadTime + decodeTime + writeTime
                ]
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                printInfo(jsonString, pipeMode: pipeOutput)
            }
        } else if !quiet {
            printInfo("Decoded: \(inputPath) -> \(outputPath)", pipeMode: pipeOutput)
            printInfo("  Input size: \(formatBytes(encodedData.count))", pipeMode: pipeOutput)
            printInfo("  Output: \(image.width)×\(image.height), \(image.componentCount) component(s)", pipeMode: pipeOutput)
            if showTiming {
                printInfo("  Timing:", pipeMode: pipeOutput)
                printInfo("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Decode: \(String(format: "%7.3f", decodeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Total:  \(String(format: "%7.3f", (loadTime + decodeTime + writeTime) * 1000)) ms", pipeMode: pipeOutput)
            }
        }
    }

    /// Parse `--region x,y,width,height` into a ``J2KRegion``.
    static func parseRegion(_ s: String) -> J2KRegion? {
        let parts = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4,
              parts[0] >= 0, parts[1] >= 0, parts[2] > 0, parts[3] > 0 else { return nil }
        return J2KRegion(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// In-process decode honouring the partial-decode options.
    ///
    /// `--region` takes precedence over `--level` (matching the API surface —
    /// the two cannot be combined in one call today).
    static func decodeInProcess(
        _ decoder: J2KDecoder,
        data: Data,
        level: Int?,
        region: J2KRegion?,
        layer: Int?,
        components: [Int]?,
        useGPUHT: Bool
    ) async throws -> J2KImage {
        if let region {
            return try await decoder.decodeRegion(data, options: J2KROIDecodingOptions(
                region: region, maxLayer: layer, components: components, strategy: .direct))
        }
        if let level {
            return try await decoder.decodeResolution(data, options: J2KResolutionDecodingOptions(
                level: level, maxLayer: layer, components: components, upscale: false))
        }
        if useGPUHT {
            return try await decoder.decodeWithGPUHT(data)
        }
        return try await decoder.decode(data)
    }

    private static func printDecodeHelp() {
        print("""
        j2k decode - Decode a JPEG 2000 image

        USAGE:
            j2k decode -i <input> [-o <output>] [options]

        OPTIONS:
            -i, --input PATH            Input file (.j2k, .jp2, .jpx)
            -o, --output PATH           Output image (optional; derived from input if omitted)
            --output-format FORMAT      Output format: pgm, ppm, tiff, png
            --level N                   Decode at resolution level N (0 = smallest
                                        thumbnail, higher = more detail; omit for
                                        full resolution). 3-8× faster for thumbnails.
                                        Values above the codestream's level count
                                        decode full resolution. NOTE: semantics
                                        changed in v10.25 — previously ignored.
            --region X,Y,W,H            Decode only the given region (true ROI
                                        decode — skips entropy work outside it).
                                        Takes precedence over --level.
            --layer N                   Quality layer (currently informational for
                                        --level/--region decodes)
            --component N               Single component index (informational)
            --components N,M,...        Component indices (informational)
            --colour-space              Convert colour space
            --gpu / --no-gpu            GPU acceleration
            --gpu-ht                    GPU HTJ2K entropy decode (Metal; HT cleanup-only)
            --verbose                   Verbose output
            --quiet                     Suppress output
            --timing                    Timing breakdown
            --json                      JSON output

        PIPING:
            -i -                        Read input from stdin
            -o -                        Write output to stdout (PNM format)
            When piping, diagnostic messages are sent to stderr.

        EXAMPLES:
            j2k decode -i input.j2k -o output.pgm
            j2k decode -i input.jp2 -o output.tiff
            j2k decode -i input.j2k
            j2k decode -i input.j2k -o - | other-tool -i -
            j2k decode -i input.jph --gpu-ht -o output.pgm
        """)
    }

    /// Wraps a raw J2K codestream in a minimal JP2 container.
    ///
    /// Builds a JP2 file with four boxes: JP2 signature, file-type, JP2 header
    /// (containing image-header and colour-specification sub-boxes), and the
    /// contiguous codestream box (`jp2c`) that holds the supplied codestream.
    ///
    /// - Parameters:
    ///   - codestream: The raw JPEG 2000 codestream bytes.
    ///   - image: The decoded image, used to populate the image-header box.
    /// - Returns: A valid JP2 file as `Data`.
    static func wrapInJP2Container(_ codestream: Data, image: J2KImage) -> Data {
        // JP2 signature box
        var out = Data()
        func appendBox(type: String, payload: Data) {
            var boxLen = UInt32(payload.count + 8).bigEndian
            out.append(contentsOf: withUnsafeBytes(of: &boxLen) { Array($0) })
            out.append(type.data(using: .ascii)!)
            out.append(payload)
        }

        // Signature box
        appendBox(type: "jP  ", payload: Data([0x0D, 0x0A, 0x87, 0x0A]))

        // File-type box
        var ftPayload = Data()
        ftPayload.append("jp2 ".data(using: .ascii)!)           // brand
        ftPayload.append(contentsOf: [0, 0, 0, 0] as [UInt8])  // minor version
        ftPayload.append("jp2 ".data(using: .ascii)!)           // compat
        appendBox(type: "ftyp", payload: ftPayload)

        // JP2 Header box (ihdr + colr)
        var ihdrPayload = Data(count: 14)
        let w = UInt32(image.width).bigEndian
        let h = UInt32(image.height).bigEndian
        let nc = UInt16(image.componentCount).bigEndian
        let bd = UInt8(image.components.first?.bitDepth ?? 8) - 1
        withUnsafeBytes(of: h) { ihdrPayload.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: w) { ihdrPayload.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: nc) { ihdrPayload.replaceSubrange(8..<10, with: $0) }
        ihdrPayload[10] = bd
        ihdrPayload[11] = 7   // C = 7 (JPEG 2000 compression)
        ihdrPayload[12] = 0   // UnkC
        ihdrPayload[13] = 0   // IPR
        appendBox(type: "ihdr", payload: ihdrPayload)

        // Codestream box
        appendBox(type: "jp2c", payload: codestream)

        return out
    }

    /// Format bytes in human-readable form
    static func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.2f %@", value, units[unitIndex])
    }
}
