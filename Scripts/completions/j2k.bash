# bash completion for j2k
# Source this file or place in /etc/bash_completion.d/j2k

_j2k() {
    local cur prev words cword
    _init_completion || return

    local commands="encode decode info transcode validate benchmark version help"

    # Determine current command
    local cmd=""
    local i
    for (( i=1; i<cword; i++ )); do
        case "${words[$i]}" in
            encode|decode|info|transcode|validate|benchmark|version|help)
                cmd="${words[$i]}"
                break
                ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        # Complete top-level commands and flags
        case "$cur" in
            --*)
                COMPREPLY=( $(compgen -W "--version --help" -- "$cur") )
                ;;
            *)
                COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
                ;;
        esac
        return
    fi

    # Per-command completion
    case "$cmd" in
        encode)
            case "$prev" in
                -i|--input)
                    _filedir '@(pgm|ppm|pnm|raw)'
                    return ;;
                -o|--output)
                    _filedir '@(j2k|jp2|jpx)'
                    return ;;
                --quality|-q)
                    COMPREPLY=( $(compgen -W "0.0 0.5 0.8 0.9 0.95 1.0" -- "$cur") )
                    return ;;
                --preset)
                    COMPREPLY=( $(compgen -W "fast balanced quality" -- "$cur") )
                    return ;;
                --format)
                    COMPREPLY=( $(compgen -W "j2k jp2 jpx" -- "$cur") )
                    return ;;
                --progression)
                    COMPREPLY=( $(compgen -W "LRCP RLCP RPCL PCRL CPRL" -- "$cur") )
                    return ;;
            esac
            COMPREPLY=( $(compgen -W "
                -i --input -o --output -q --quality
                --lossless --bitrate --psnr --visually-lossless
                --preset --levels --blocksize --layers --format
                --progression --tile-size --roi --htj2k --mct --no-mct
                --gpu --no-gpu --colour-space --color-space
                --verbose --quiet --timing --json --help
            " -- "$cur") )
            ;;
        decode)
            case "$prev" in
                -i|--input)
                    _filedir '@(j2k|jp2|jpx|jpc)'
                    return ;;
                -o|--output)
                    _filedir '@(pgm|ppm|raw)'
                    return ;;
            esac
            COMPREPLY=( $(compgen -W "
                -i --input -o --output
                --level --layer --component --components
                --colour-space --color-space --gpu --no-gpu
                --verbose --quiet --timing --json --help
            " -- "$cur") )
            ;;
        info)
            case "$prev" in
                info|-i|--input)
                    _filedir '@(j2k|jp2|jpx|jpc)'
                    return ;;
            esac
            COMPREPLY=( $(compgen -W "--markers --boxes --json --validate --help" -- "$cur") )
            ;;
        transcode)
            case "$prev" in
                -i|--input)
                    _filedir '@(j2k|jp2|jpx|jpc)'
                    return ;;
                -o|--output)
                    _filedir '@(j2k|jp2|jpx)'
                    return ;;
                --batch|--output-dir)
                    _filedir -d
                    return ;;
                --format)
                    COMPREPLY=( $(compgen -W "j2k jp2 jpx" -- "$cur") )
                    return ;;
                --progression)
                    COMPREPLY=( $(compgen -W "LRCP RLCP RPCL PCRL CPRL" -- "$cur") )
                    return ;;
            esac
            COMPREPLY=( $(compgen -W "
                -i --input -o --output
                --to-htj2k --from-htj2k --format
                --quality --bitrate --layers --progression
                --batch --output-dir --verbose --quiet --help
            " -- "$cur") )
            ;;
        validate)
            case "$prev" in
                validate|-i|--input)
                    _filedir '@(j2k|jp2|jpx|jpc)'
                    return ;;
            esac
            COMPREPLY=( $(compgen -W "--part1 --part2 --part15 --strict --json --quiet --help" -- "$cur") )
            ;;
        benchmark)
            case "$prev" in
                -i|--input)
                    _filedir '@(pgm|ppm|pnm|raw)'
                    return ;;
                -o|--output)
                    _filedir '@(json|csv|txt)'
                    return ;;
                --preset)
                    COMPREPLY=( $(compgen -W "fast balanced quality" -- "$cur") )
                    return ;;
                --format)
                    COMPREPLY=( $(compgen -W "text json csv" -- "$cur") )
                    return ;;
            esac
            COMPREPLY=( $(compgen -W "
                -i --input -r --runs --warmup -o --output
                --format --encode-only --decode-only --preset
                --compare-openjpeg --help
            " -- "$cur") )
            ;;
    esac
}

complete -F _j2k j2k
