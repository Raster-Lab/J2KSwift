//
// RootTabView.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// App shell. The image Viewer is currently hidden: the app shows only
// the Benchmarks flow. Flip `showViewer` to `true` to restore the
// two-tab layout — `ViewerView` and all its supporting code remain in
// the target, just unreferenced from the UI.

import SwiftUI
import J2KCodec

struct RootTabView: View {

    /// The image Viewer tab is hidden for now. Set to `true` to bring
    /// back the Benchmarks / Viewer tab bar.
    private let showViewer = false

    var body: some View {
        content
            .task {
                // Warm the shared Metal session once at startup.
                await J2KDecoder.preWarm(includeWarmupDispatch: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        if showViewer {
            TabView {
                HistoryView()
                    .tabItem {
                        Label("Benchmarks", systemImage: "speedometer")
                    }
                ViewerView()
                    .tabItem {
                        Label("Viewer", systemImage: "photo")
                    }
            }
        } else {
            HistoryView()
        }
    }
}
