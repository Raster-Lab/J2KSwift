//
// RootTabView.swift
// J2KBenchApp — v10.5 cross-silicon bench + v10.18 JP3D arc
//
// App shell. Two visible tabs in v10.18:
//   • Benchmarks — the 2D codec bench (encode + 3 decode lanes)
//   • Volumes    — the 3D JP3D bench + MPR viewer
// The legacy image Viewer tab is gated off (`showViewer = false`);
// `ViewerView` and its support code remain in the target, just
// unreferenced from the UI.

import SwiftUI
import J2KCodec

struct RootTabView: View {

    /// 2D image Viewer remains hidden — Volumes (MPR viewer for JP3D)
    /// supersedes it for the v10.18-research arc. Flip back to `true`
    /// to bring the 2D viewer tab back.
    private let showImageViewer = false

    var body: some View {
        content
            .task {
                // Warm the shared Metal session once at startup. Both
                // the 2D bench/viewer and the JP3D per-slice decode
                // benefit (JP3D per-slice goes through J2KDecoder).
                await J2KDecoder.preWarm(includeWarmupDispatch: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        TabView {
            HistoryView()
                .tabItem {
                    Label("Benchmarks", systemImage: "speedometer")
                }
            JP3DHistoryView()
                .tabItem {
                    Label("Volumes", systemImage: "cube.transparent")
                }
            if showImageViewer {
                ViewerView()
                    .tabItem {
                        Label("Viewer", systemImage: "photo")
                    }
            }
        }
    }
}
