//
// Entry.swift
// J2KSwift
//
// Thin executable entry point for the `j2k` CLI. All command logic
// lives in the J2KCLICore library target so test targets can link it
// without inheriting an executable `@main` (which would hijack the
// swift-testing pass of `swift test` and force a non-zero exit).
import J2KCLICore

@main
struct J2KCLIEntryPoint {
    static func main() async {
        await J2KCLICore.J2KCLI.run()
    }
}
