#compdef j2k
# zsh completion for j2k
# Place in a directory on $fpath, then run: autoload -Uz compinit && compinit

local commands=(
    'encode:Encode an image to JPEG 2000'
    'decode:Decode a JPEG 2000 image'
    'info:Display codestream information'
    'transcode:Transcode between JPEG 2000 formats'
    'validate:Validate a JPEG 2000 codestream'
    'benchmark:Run encoding/decoding benchmarks'
    'version:Print version information'
    'help:Show help message'
)

local progression_orders=(LRCP RLCP RPCL PCRL CPRL)
local presets=(fast balanced quality)
local formats=(j2k jp2 jpx)
local bench_formats=(text json csv)

_j2k_encode() {
    _arguments \
        '(-i --input)'{-i,--input}'[Input image file]:input file:_files -g "*.pgm *.ppm *.pnm *.raw"' \
        '(-o --output)'{-o,--output}'[Output JPEG 2000 file]:output file:_files -g "*.j2k *.jp2 *.jpx"' \
        '(-q --quality)'{-q,--quality}'[Quality 0.0-1.0]:quality:(0.0 0.5 0.8 0.9 0.95 1.0)' \
        '--lossless[Lossless compression]' \
        '--bitrate[Target bit-rate in BPP]:bits per pixel' \
        '--psnr[Target PSNR]:dB' \
        '--visually-lossless[Near-lossless mode]' \
        '--preset[Encoding preset]:preset:('"${presets[*]}"')' \
        '--levels[Decomposition levels]:levels' \
        '--blocksize[Code-block size]:WxH' \
        '--layers[Quality layers]:count' \
        '--format[Output format]:format:('"${formats[*]}"')' \
        '--progression[Progression order]:order:('"${progression_orders[*]}"')' \
        '--tile-size[Tile size]:WxH' \
        '--roi[Region of interest]:x,y,w,h' \
        '--htj2k[Enable HTJ2K]' \
        '--mct[Enable MCT]' \
        '--no-mct[Disable MCT]' \
        '--gpu[Enable GPU]' \
        '--no-gpu[Disable GPU]' \
        '--colour-space[Set colour space]:colour space' \
        '--color-space[Set color space]:color space' \
        '--verbose[Verbose output]' \
        '--quiet[Quiet mode]' \
        '--timing[Show timing]' \
        '--json[JSON output]' \
        '--help[Show help]'
}

_j2k_decode() {
    _arguments \
        '(-i --input)'{-i,--input}'[Input JPEG 2000 file]:input file:_files -g "*.j2k *.jp2 *.jpx *.jpc"' \
        '(-o --output)'{-o,--output}'[Output image file]:output file:_files -g "*.pgm *.ppm *.raw"' \
        '--level[Resolution level]:level' \
        '--layer[Quality layer]:layer' \
        '--component[Component index]:index' \
        '--components[Component indices]:N,M,...' \
        '--colour-space[Colour space conversion]' \
        '--color-space[Color space conversion]' \
        '--gpu[Enable GPU]' \
        '--no-gpu[Disable GPU]' \
        '--verbose[Verbose output]' \
        '--quiet[Quiet mode]' \
        '--timing[Show timing]' \
        '--json[JSON output]' \
        '--help[Show help]'
}

_j2k_info() {
    _arguments \
        '1:JPEG 2000 file:_files -g "*.j2k *.jp2 *.jpx *.jpc"' \
        '--markers[List marker segments]' \
        '--boxes[List JP2 boxes]' \
        '--json[JSON output]' \
        '--validate[Quick validation check]' \
        '--help[Show help]'
}

_j2k_transcode() {
    _arguments \
        '(-i --input)'{-i,--input}'[Input file]:input file:_files -g "*.j2k *.jp2 *.jpx *.jpc"' \
        '(-o --output)'{-o,--output}'[Output file]:output file:_files -g "*.j2k *.jp2 *.jpx"' \
        '--to-htj2k[Transcode to HTJ2K]' \
        '--from-htj2k[Transcode from HTJ2K]' \
        '--format[Output format]:format:('"${formats[*]}"')' \
        '--quality[Quality]:0.0-1.0' \
        '--bitrate[Bit-rate]:BPP' \
        '--layers[Quality layers]:count' \
        '--progression[Progression order]:order:('"${progression_orders[*]}"')' \
        '--batch[Batch input directory]:directory:_files -/' \
        '--output-dir[Output directory]:directory:_files -/' \
        '--verbose[Verbose output]' \
        '--quiet[Quiet mode]' \
        '--help[Show help]'
}

_j2k_validate() {
    _arguments \
        '1:JPEG 2000 file:_files -g "*.j2k *.jp2 *.jpx *.jpc"' \
        '--part1[Part 1 conformance]' \
        '--part2[Part 2 conformance]' \
        '--part15[Part 15 HTJ2K conformance]' \
        '--strict[Strict mode]' \
        '--json[JSON output]' \
        '--quiet[Quiet mode]' \
        '--help[Show help]'
}

_j2k_benchmark() {
    _arguments \
        '(-i --input)'{-i,--input}'[Input image]:input file:_files -g "*.pgm *.ppm *.pnm *.raw"' \
        '(-r --runs)'{-r,--runs}'[Number of runs]:count' \
        '--warmup[Warm-up runs]:count' \
        '(-o --output)'{-o,--output}'[Output report]:output file:_files' \
        '--format[Output format]:format:('"${bench_formats[*]}"')' \
        '--encode-only[Encode only]' \
        '--decode-only[Decode only]' \
        '--preset[Preset]:preset:('"${presets[*]}"')' \
        '--compare-openjpeg[Compare with OpenJPEG]' \
        '--help[Show help]'
}

_j2k() {
    local context state line
    typeset -A opt_args

    _arguments -C \
        '--version[Print version]' \
        '(-h --help)'{-h,--help}'[Show help]' \
        ':command:->command' \
        '*::options:->options'

    case $state in
        command)
            _describe 'j2k commands' commands
            ;;
        options)
            case $line[1] in
                encode)    _j2k_encode    ;;
                decode)    _j2k_decode    ;;
                info)      _j2k_info      ;;
                transcode) _j2k_transcode ;;
                validate)  _j2k_validate  ;;
                benchmark) _j2k_benchmark ;;
            esac
            ;;
    esac
}

_j2k "$@"
