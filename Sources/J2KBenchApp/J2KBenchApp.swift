//
// J2KBenchApp.swift
// v10.5 cross-silicon arc — shareable iOS bench app.
//
// Companion to `Scripts/benchmarks/run_canonical_bench.sh`. The shell
// runner can't deploy to A-series silicon (no fork/exec, no launchd
// daemon, no kdu_expand on iOS); this SwiftUI app fills that gap. A
// recipient installs and taps "Run Benchmark"; the app produces a
// JSON file that the project team feeds into
// `Scripts/benchmarks/compare_hosts.py` alongside the M2/M4 baselines.

import SwiftUI

@main
struct J2KBenchApp: App {
    var body: some Scene {
        WindowGroup {
            BenchView()
        }
    }
}
