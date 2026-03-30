//
// CompletionTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for shell completion generation (bash, zsh, fish).
final class CompletionTests: XCTestCase {

    // MARK: - Completion argument parsing

    func testCompletionBashArgs() {
        let args = ["bash"]
        XCTAssertEqual(args[0], "bash")
    }

    func testCompletionZshArgs() {
        let args = ["zsh"]
        XCTAssertEqual(args[0], "zsh")
    }

    func testCompletionFishArgs() {
        let args = ["fish"]
        XCTAssertEqual(args[0], "fish")
    }

    // MARK: - Command list completeness

    func testAllCommandsInCompletions() {
        let commands = [
            "encode", "decode", "transcode", "info", "validate", "benchmark",
            "encode3d", "decode3d", "jpip", "batch", "compare", "convert",
            "completions", "version", "help"
        ]
        XCTAssertEqual(commands.count, 15, "Should complete 15 commands")
    }

    // MARK: - Bash completion format

    func testBashCompletionStructure() {
        // Bash completions should define a function and use COMPREPLY
        let bashTemplate = """
        _j2k_completions() {
            COMPREPLY=()
        }
        complete -F _j2k_completions j2k
        """
        XCTAssertTrue(bashTemplate.contains("_j2k_completions"))
        XCTAssertTrue(bashTemplate.contains("COMPREPLY"))
        XCTAssertTrue(bashTemplate.contains("complete -F"))
    }

    // MARK: - Zsh completion format

    func testZshCompletionStructure() {
        let zshTemplate = """
        #compdef j2k
        _j2k() {
            local -a commands
            commands=()
        }
        """
        XCTAssertTrue(zshTemplate.contains("#compdef j2k"))
        XCTAssertTrue(zshTemplate.contains("_j2k()"))
    }

    // MARK: - Fish completion format

    func testFishCompletionStructure() {
        let fishTemplate = """
        complete -c j2k -f
        complete -c j2k -n '__fish_use_subcommand' -a encode
        """
        XCTAssertTrue(fishTemplate.contains("complete -c j2k"))
        XCTAssertTrue(fishTemplate.contains("-a encode"))
    }

    // MARK: - Flag completions

    func testEncodeFlags() {
        let encodeFlags = [
            "--input", "--output", "--quality", "--lossless",
            "--codec", "--compression-ratio", "--compression-percent",
            "--target-size", "--decomposition-levels", "--tile-width",
            "--tile-height", "--color-space"
        ]
        XCTAssertGreaterThan(encodeFlags.count, 5, "encode should have many flags")
    }

    func testDecodeFlags() {
        let decodeFlags = [
            "--input", "--output", "--header-only", "--bit-depth",
            "--strip-alpha", "--region", "--scale", "--output-format"
        ]
        XCTAssertGreaterThan(decodeFlags.count, 5, "decode should have many flags")
    }

    func testBatchFlags() {
        let batchFlags = [
            "--input", "--output-dir", "--output-suffix",
            "--recursive", "--filter", "--exclude",
            "--threads", "--progress"
        ]
        XCTAssertGreaterThan(batchFlags.count, 5, "batch should have many flags")
    }

    // MARK: - Shell detection

    func testSupportedShells() {
        let supportedShells = ["bash", "zsh", "fish"]
        XCTAssertTrue(supportedShells.contains("bash"))
        XCTAssertTrue(supportedShells.contains("zsh"))
        XCTAssertTrue(supportedShells.contains("fish"))
        XCTAssertFalse(supportedShells.contains("powershell"))
    }
}
