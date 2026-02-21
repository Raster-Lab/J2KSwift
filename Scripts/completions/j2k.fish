# fish completion for j2k
# Place in ~/.config/fish/completions/j2k.fish

# Helper: disable file completion for a subcommand when no positional arg expected
function __j2k_no_files
    set -l cmd (commandline -poc)
    if string match -q -- '* encode *' $cmd; or \
       string match -q -- '* decode *' $cmd; or \
       string match -q -- '* benchmark *' $cmd
        return 0
    end
    return 1
end

# Detect current subcommand
function __j2k_subcommand
    set -l words (commandline -poc)
    for w in $words[2..]
        switch $w
            case encode decode info transcode validate benchmark version help
                echo $w
                return
        end
    end
end

# Top-level commands
complete -c j2k -f -n 'not __j2k_subcommand' -a encode      -d 'Encode an image to JPEG 2000'
complete -c j2k -f -n 'not __j2k_subcommand' -a decode      -d 'Decode a JPEG 2000 image'
complete -c j2k -f -n 'not __j2k_subcommand' -a info        -d 'Display codestream information'
complete -c j2k -f -n 'not __j2k_subcommand' -a transcode   -d 'Transcode between JPEG 2000 formats'
complete -c j2k -f -n 'not __j2k_subcommand' -a validate    -d 'Validate a JPEG 2000 codestream'
complete -c j2k -f -n 'not __j2k_subcommand' -a benchmark   -d 'Run benchmarks'
complete -c j2k -f -n 'not __j2k_subcommand' -a version     -d 'Print version'
complete -c j2k -f -n 'not __j2k_subcommand' -a help        -d 'Show help'
complete -c j2k -f -n 'not __j2k_subcommand' -l version     -d 'Print version and exit'
complete -c j2k -f -n 'not __j2k_subcommand' -s h -l help   -d 'Show help'

# ── encode ────────────────────────────────────────────────────────────────────
complete -c j2k -n '__j2k_subcommand | string match encode' -s i -l input      -r -d 'Input image (PGM, PPM, PNM, RAW)'
complete -c j2k -n '__j2k_subcommand | string match encode' -s o -l output     -r -d 'Output file (.j2k, .jp2, .jpx)'
complete -c j2k -n '__j2k_subcommand | string match encode' -s q -l quality    -r -d 'Quality 0.0-1.0'
complete -c j2k -n '__j2k_subcommand | string match encode' -l lossless           -d 'Lossless compression'
complete -c j2k -n '__j2k_subcommand | string match encode' -l bitrate         -r -d 'Target bit-rate (BPP)'
complete -c j2k -n '__j2k_subcommand | string match encode' -l psnr            -r -d 'Target PSNR (dB)'
complete -c j2k -n '__j2k_subcommand | string match encode' -l visually-lossless  -d 'Near-lossless mode'
complete -c j2k -n '__j2k_subcommand | string match encode' -l preset          -r -d 'Preset: fast, balanced, quality'
complete -c j2k -n '__j2k_subcommand | string match encode' -l levels          -r -d 'DWT levels'
complete -c j2k -n '__j2k_subcommand | string match encode' -l blocksize       -r -d 'Code-block size (WxH)'
complete -c j2k -n '__j2k_subcommand | string match encode' -l layers          -r -d 'Quality layers'
complete -c j2k -n '__j2k_subcommand | string match encode' -l format          -r -d 'Output format: j2k, jp2, jpx'
complete -c j2k -n '__j2k_subcommand | string match encode' -l progression     -r -d 'Progression order'
complete -c j2k -n '__j2k_subcommand | string match encode' -l tile-size       -r -d 'Tile size (WxH)'
complete -c j2k -n '__j2k_subcommand | string match encode' -l roi             -r -d 'Region of interest (x,y,w,h)'
complete -c j2k -n '__j2k_subcommand | string match encode' -l htj2k              -d 'Enable HTJ2K'
complete -c j2k -n '__j2k_subcommand | string match encode' -l mct               -d 'Enable MCT'
complete -c j2k -n '__j2k_subcommand | string match encode' -l no-mct            -d 'Disable MCT'
complete -c j2k -n '__j2k_subcommand | string match encode' -l gpu               -d 'Enable GPU'
complete -c j2k -n '__j2k_subcommand | string match encode' -l no-gpu            -d 'Disable GPU'
complete -c j2k -n '__j2k_subcommand | string match encode' -l colour-space   -r -d 'Set colour space'
complete -c j2k -n '__j2k_subcommand | string match encode' -l color-space    -r -d 'Set color space'
complete -c j2k -n '__j2k_subcommand | string match encode' -l verbose            -d 'Verbose output'
complete -c j2k -n '__j2k_subcommand | string match encode' -l quiet              -d 'Quiet mode'
complete -c j2k -n '__j2k_subcommand | string match encode' -l timing             -d 'Show timing'
complete -c j2k -n '__j2k_subcommand | string match encode' -l json               -d 'JSON output'
complete -c j2k -n '__j2k_subcommand | string match encode' -l help               -d 'Show help'

# ── decode ────────────────────────────────────────────────────────────────────
complete -c j2k -n '__j2k_subcommand | string match decode' -s i -l input      -r -d 'Input JPEG 2000 file'
complete -c j2k -n '__j2k_subcommand | string match decode' -s o -l output     -r -d 'Output image file'
complete -c j2k -n '__j2k_subcommand | string match decode' -l level           -r -d 'Resolution level'
complete -c j2k -n '__j2k_subcommand | string match decode' -l layer           -r -d 'Quality layer'
complete -c j2k -n '__j2k_subcommand | string match decode' -l component       -r -d 'Component index'
complete -c j2k -n '__j2k_subcommand | string match decode' -l components      -r -d 'Component indices'
complete -c j2k -n '__j2k_subcommand | string match decode' -l colour-space       -d 'Colour space conversion'
complete -c j2k -n '__j2k_subcommand | string match decode' -l color-space        -d 'Color space conversion'
complete -c j2k -n '__j2k_subcommand | string match decode' -l gpu               -d 'Enable GPU'
complete -c j2k -n '__j2k_subcommand | string match decode' -l no-gpu            -d 'Disable GPU'
complete -c j2k -n '__j2k_subcommand | string match decode' -l verbose            -d 'Verbose output'
complete -c j2k -n '__j2k_subcommand | string match decode' -l quiet              -d 'Quiet mode'
complete -c j2k -n '__j2k_subcommand | string match decode' -l timing             -d 'Show timing'
complete -c j2k -n '__j2k_subcommand | string match decode' -l json               -d 'JSON output'
complete -c j2k -n '__j2k_subcommand | string match decode' -l help               -d 'Show help'

# ── info ──────────────────────────────────────────────────────────────────────
complete -c j2k -n '__j2k_subcommand | string match info' -l markers    -d 'List marker segments'
complete -c j2k -n '__j2k_subcommand | string match info' -l boxes      -d 'List JP2 boxes'
complete -c j2k -n '__j2k_subcommand | string match info' -l json       -d 'JSON output'
complete -c j2k -n '__j2k_subcommand | string match info' -l validate   -d 'Quick validation'
complete -c j2k -n '__j2k_subcommand | string match info' -l help       -d 'Show help'

# ── transcode ─────────────────────────────────────────────────────────────────
complete -c j2k -n '__j2k_subcommand | string match transcode' -s i -l input       -r -d 'Input JPEG 2000 file'
complete -c j2k -n '__j2k_subcommand | string match transcode' -s o -l output      -r -d 'Output JPEG 2000 file'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l to-htj2k            -d 'Transcode to HTJ2K'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l from-htj2k          -d 'Transcode from HTJ2K'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l format           -r -d 'Output format'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l quality          -r -d 'Quality 0.0-1.0'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l bitrate          -r -d 'Bit-rate (BPP)'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l layers           -r -d 'Quality layers'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l progression      -r -d 'Progression order'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l batch            -r -d 'Input directory (batch)'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l output-dir       -r -d 'Output directory (batch)'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l verbose             -d 'Verbose output'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l quiet               -d 'Quiet mode'
complete -c j2k -n '__j2k_subcommand | string match transcode' -l help                -d 'Show help'

# ── validate ──────────────────────────────────────────────────────────────────
complete -c j2k -n '__j2k_subcommand | string match validate' -l part1   -d 'Part 1 conformance'
complete -c j2k -n '__j2k_subcommand | string match validate' -l part2   -d 'Part 2 conformance'
complete -c j2k -n '__j2k_subcommand | string match validate' -l part15  -d 'Part 15 HTJ2K conformance'
complete -c j2k -n '__j2k_subcommand | string match validate' -l strict  -d 'Strict mode'
complete -c j2k -n '__j2k_subcommand | string match validate' -l json    -d 'JSON output'
complete -c j2k -n '__j2k_subcommand | string match validate' -l quiet   -d 'Quiet mode'
complete -c j2k -n '__j2k_subcommand | string match validate' -l help    -d 'Show help'

# ── benchmark ─────────────────────────────────────────────────────────────────
complete -c j2k -n '__j2k_subcommand | string match benchmark' -s i -l input           -r -d 'Input image'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -s r -l runs            -r -d 'Number of runs'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -l warmup               -r -d 'Warm-up runs'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -s o -l output          -r -d 'Output report file'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -l format               -r -d 'Output format: text, json, csv'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -l encode-only             -d 'Encode-only benchmark'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -l decode-only             -d 'Decode-only benchmark'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -l preset               -r -d 'Encoding preset'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -l compare-openjpeg        -d 'Compare with OpenJPEG'
complete -c j2k -n '__j2k_subcommand | string match benchmark' -l help                    -d 'Show help'
