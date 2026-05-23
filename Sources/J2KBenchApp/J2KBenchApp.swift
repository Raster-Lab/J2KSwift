//
// J2KBenchApp.swift
// v10.5 cross-silicon arc — shareable iOS bench app.
// v10.18-research JP3D arc — adds the Volumes tab (JP3D bench + MPR
// viewer). Two persisted run-histories share the shell: `BenchStore`
// for the 2D Benchmarks tab, `JP3DBenchStore` for the Volumes tab.

import SwiftUI

@main
struct J2KBenchApp: App {
    /// 2D run-history store (Benchmarks tab).
    @StateObject private var store = BenchStore()
    /// 3D run-history store (Volumes tab).
    @StateObject private var jp3dStore = JP3DBenchStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(jp3dStore)
        }
    }
}
