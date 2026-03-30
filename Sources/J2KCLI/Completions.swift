//
// Completions.swift
// J2KSwift
//
/// Shell completion generation for bash, zsh, and fish.

import Foundation

extension J2KCLI {

    /// Generate shell completions for the specified shell.
    static func completionsCommand(_ args: [String]) async throws {
        guard let shell = args.first else {
            print("Usage: j2k completions <bash|zsh|fish>")
            exit(1)
        }

        switch shell.lowercased() {
        case "bash":
            print(generateBashCompletions())
        case "zsh":
            print(generateZshCompletions())
        case "fish":
            print(generateFishCompletions())
        default:
            print("Error: Unknown shell '\(shell)'. Supported: bash, zsh, fish")
            exit(1)
        }
    }

    // MARK: - Bash Completions

    private static func generateBashCompletions() -> String {
        return """
        # Bash completion for j2k
        # Install: j2k completions bash > /etc/bash_completion.d/j2k
        #   or:    j2k completions bash >> ~/.bashrc

        _j2k_completions() {
            local cur prev commands
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"

            commands="encode decode transcode info validate benchmark encode3d decode3d jpip batch compare convert completions version help"

            if [[ ${COMP_CWORD} -eq 1 ]]; then
                COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
                return 0
            fi

            case "${COMP_WORDS[1]}" in
                encode)
                    COMPREPLY=( $(compgen -W "-i --input -o --output -q --quality --lossless --bitrate --psnr --visually-lossless --preset --levels --blocksize --layers --format --progression --tile-size --htj2k --mct --no-mct --gpu --no-gpu --codec --compression-ratio --compression-percent --target-size --roi --roi-file --estimate --memory-limit --colour-space --color-space --threads --verbose --quiet --timing --json --progress --help" -- ${cur}) )
                    ;;
                decode)
                    COMPREPLY=( $(compgen -W "-i --input -o --output --level --layer --component --components --region --scale --strip-alpha --output-format --bit-depth --color-convert --header-only --gpu --no-gpu --threads --verbose --quiet --timing --json --help" -- ${cur}) )
                    ;;
                transcode)
                    COMPREPLY=( $(compgen -W "-i --input -o --output --to-htj2k --from-htj2k --format --quality --bitrate --layers --progression --batch --output-dir --verify --verify-mode --preserve-metadata --strip-metadata --threads --report --continue-on-error --verbose --quiet --json --help" -- ${cur}) )
                    ;;
                info)
                    COMPREPLY=( $(compgen -W "--markers --boxes --json --validate --capabilities --list-gpus --help" -- ${cur}) )
                    ;;
                validate)
                    COMPREPLY=( $(compgen -W "--part1 --part2 --part15 --strict --json --quiet --help" -- ${cur}) )
                    ;;
                benchmark)
                    COMPREPLY=( $(compgen -W "-i --input -r --runs --warmup -o --output --format --encode-only --decode-only --preset --compare-openjpeg --mode --help" -- ${cur}) )
                    ;;
                encode3d)
                    COMPREPLY=( $(compgen -W "-i --input -o --output --codec --dimensions --bit-depth --frames --compression-ratio --compression-percent --tile-size --decomposition-levels --progression --parallel --no-parallel --psnr --verbose --quiet --timing --json --help" -- ${cur}) )
                    ;;
                decode3d)
                    COMPREPLY=( $(compgen -W "-i --input -o --output --output-format --slice-range --region --scale --slice-naming --verbose --quiet --timing --json --help" -- ${cur}) )
                    ;;
                jpip)
                    if [[ ${COMP_CWORD} -eq 2 ]]; then
                        COMPREPLY=( $(compgen -W "server client" -- ${cur}) )
                    fi
                    ;;
                batch)
                    if [[ ${COMP_CWORD} -eq 2 ]]; then
                        COMPREPLY=( $(compgen -W "encode decode transcode encode3d decode3d" -- ${cur}) )
                    else
                        COMPREPLY=( $(compgen -W "-i --input -o --output --recursive --filter --exclude --output-suffix --continue-on-error --threads --progress --verbose --quiet --json --help" -- ${cur}) )
                    fi
                    ;;
                compare)
                    COMPREPLY=( $(compgen -W "-i --input -r --reference --mode --bit-exact --json --quiet --help" -- ${cur}) )
                    ;;
                convert)
                    COMPREPLY=( $(compgen -W "-i --input -o --output --bit-depth --output-format --verbose --quiet --json --help" -- ${cur}) )
                    ;;
                completions)
                    COMPREPLY=( $(compgen -W "bash zsh fish" -- ${cur}) )
                    ;;
            esac
            return 0
        }
        complete -F _j2k_completions j2k
        """
    }

    // MARK: - Zsh Completions

    private static func generateZshCompletions() -> String {
        return """
        #compdef j2k
        # Zsh completion for j2k
        # Install: j2k completions zsh > ~/.zsh/completions/_j2k

        _j2k() {
            local -a commands
            commands=(
                'encode:Compress image(s) to JPEG 2000 / HTJ2K'
                'decode:Decompress JPEG 2000 / HTJ2K image(s)'
                'transcode:Lossless transcoding between J2K and HTJ2K'
                'info:Display codestream / file-format metadata'
                'validate:Conformance validation'
                'benchmark:Performance benchmarking'
                'encode3d:Compress volumetric / 3D data (JP3D)'
                'decode3d:Decompress volumetric / 3D data (JP3D)'
                'jpip:JPIP streaming (server/client)'
                'batch:Batch-process files in a directory'
                'compare:Compare two images (PSNR, SSIM, MSE)'
                'convert:Convert between image formats'
                'completions:Generate shell completions'
                'version:Print version information'
                'help:Show help for command'
            )

            _arguments -C \\
                '--version[Print version and exit]' \\
                '--help[Show help]' \\
                '1:command:->command' \\
                '*::arg:->args'

            case "$state" in
                command)
                    _describe 'command' commands
                    ;;
                args)
                    case "${words[1]}" in
                        encode)
                            _arguments \\
                                '-i[Input file]:file:_files' \\
                                '--input[Input file]:file:_files' \\
                                '-o[Output file]:file:_files' \\
                                '--output[Output file]:file:_files' \\
                                '-q[Quality 0.0-1.0]:quality:' \\
                                '--quality[Quality 0.0-1.0]:quality:' \\
                                '--lossless[Lossless compression]' \\
                                '--htj2k[Use HTJ2K encoding]' \\
                                '--codec[Codec variant]:codec:(j2k-lossless j2k-lossy htj2k-lossless htj2k-lossy htj2k-lossless-rpcl)' \\
                                '--preset[Encoding preset]:preset:(fast balanced quality)' \\
                                '--format[Output format]:format:(j2k jp2 jpx jph)' \\
                                '--verbose[Verbose output]' \\
                                '--quiet[Suppress output]' \\
                                '--timing[Show timing]' \\
                                '--json[JSON output]'
                            ;;
                        decode)
                            _arguments \\
                                '-i[Input file]:file:_files' \\
                                '--input[Input file]:file:_files' \\
                                '-o[Output file]:file:_files' \\
                                '--output[Output file]:file:_files' \\
                                '--region[Decode region]:region:' \\
                                '--scale[Resolution reduction]:scale:(1 2 4 8)' \\
                                '--output-format[Output format]:format:(pgm ppm pnm raw)' \\
                                '--verbose[Verbose output]' \\
                                '--quiet[Suppress output]' \\
                                '--json[JSON output]'
                            ;;
                    esac
                    ;;
            esac
        }

        _j2k "$@"
        """
    }

    // MARK: - Fish Completions

    private static func generateFishCompletions() -> String {
        return """
        # Fish completion for j2k
        # Install: j2k completions fish > ~/.config/fish/completions/j2k.fish

        # Main commands
        complete -c j2k -n '__fish_use_subcommand' -a encode -d 'Compress image(s) to JPEG 2000'
        complete -c j2k -n '__fish_use_subcommand' -a decode -d 'Decompress JPEG 2000 image(s)'
        complete -c j2k -n '__fish_use_subcommand' -a transcode -d 'Lossless transcoding'
        complete -c j2k -n '__fish_use_subcommand' -a info -d 'Display codestream metadata'
        complete -c j2k -n '__fish_use_subcommand' -a validate -d 'Conformance validation'
        complete -c j2k -n '__fish_use_subcommand' -a benchmark -d 'Performance benchmarking'
        complete -c j2k -n '__fish_use_subcommand' -a encode3d -d 'Compress 3D volumetric data'
        complete -c j2k -n '__fish_use_subcommand' -a decode3d -d 'Decompress 3D volumetric data'
        complete -c j2k -n '__fish_use_subcommand' -a jpip -d 'JPIP streaming'
        complete -c j2k -n '__fish_use_subcommand' -a batch -d 'Batch-process files'
        complete -c j2k -n '__fish_use_subcommand' -a compare -d 'Compare two images'
        complete -c j2k -n '__fish_use_subcommand' -a convert -d 'Convert image formats'
        complete -c j2k -n '__fish_use_subcommand' -a completions -d 'Generate shell completions'
        complete -c j2k -n '__fish_use_subcommand' -a version -d 'Print version'
        complete -c j2k -n '__fish_use_subcommand' -a help -d 'Show help'

        # Global flags
        complete -c j2k -l version -d 'Print version and exit'
        complete -c j2k -l help -d 'Show help'
        complete -c j2k -l verbose -d 'Verbose output'
        complete -c j2k -l quiet -d 'Suppress output'
        complete -c j2k -l json -d 'JSON output'
        complete -c j2k -l timing -d 'Show timing'
        complete -c j2k -l progress -d 'Show progress'

        # Encode options
        complete -c j2k -n '__fish_seen_subcommand_from encode' -s i -l input -r -d 'Input file'
        complete -c j2k -n '__fish_seen_subcommand_from encode' -s o -l output -r -d 'Output file'
        complete -c j2k -n '__fish_seen_subcommand_from encode' -s q -l quality -r -d 'Quality 0.0-1.0'
        complete -c j2k -n '__fish_seen_subcommand_from encode' -l lossless -d 'Lossless compression'
        complete -c j2k -n '__fish_seen_subcommand_from encode' -l htj2k -d 'Use HTJ2K'
        complete -c j2k -n '__fish_seen_subcommand_from encode' -l codec -r -a 'j2k-lossless j2k-lossy htj2k-lossless htj2k-lossy' -d 'Codec variant'
        complete -c j2k -n '__fish_seen_subcommand_from encode' -l preset -r -a 'fast balanced quality' -d 'Encoding preset'
        complete -c j2k -n '__fish_seen_subcommand_from encode' -l format -r -a 'j2k jp2 jpx jph' -d 'Output format'

        # Decode options
        complete -c j2k -n '__fish_seen_subcommand_from decode' -s i -l input -r -d 'Input file'
        complete -c j2k -n '__fish_seen_subcommand_from decode' -s o -l output -r -d 'Output file'
        complete -c j2k -n '__fish_seen_subcommand_from decode' -l region -r -d 'Decode region x,y,w,h'
        complete -c j2k -n '__fish_seen_subcommand_from decode' -l scale -r -a '1 2 4 8' -d 'Resolution reduction'
        complete -c j2k -n '__fish_seen_subcommand_from decode' -l output-format -r -a 'pgm ppm pnm raw' -d 'Output format'

        # Completions subcommand
        complete -c j2k -n '__fish_seen_subcommand_from completions' -a 'bash zsh fish' -d 'Shell type'
        """
    }
}
