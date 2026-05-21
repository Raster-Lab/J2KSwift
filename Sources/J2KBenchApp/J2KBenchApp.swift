//
// J2KBenchApp.swift
// v10.5 cross-silicon arc — shareable iOS bench app.
//
// Shell is `RootTabView`. The Benchmarks flow runs the warm in-process
// bench on A-series silicon, saves each run on-device, and shares the
// canonical JSON `compare_hosts.py` ingests. The image Viewer is built
// but currently hidden — see `RootTabView.showViewer`.

import SwiftUI

@main
struct J2KBenchApp: App {
    /// One shared run-history store for the whole app.
    @StateObject private var store = BenchStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
        }
    }
}
