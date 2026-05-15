//
// BenchView.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Single-screen SwiftUI surface. Top: device identification + run
// controls. Body: per-fixture result table that fills in as the bench
// progresses. Bottom: share button that exports the canonical JSON
// blob via UIActivityViewController on iOS / NSSharingService picker
// on macOS.

import SwiftUI

struct BenchView: View {
    @StateObject private var model = BenchModel()
    @State private var isRunning = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                hostHeader
                Divider()
                runControls
                Divider()
                resultsList
                Divider()
                footer
            }
            .navigationTitle("J2KSwift A-Series Bench")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        #endif
    }

    // MARK: - Header

    private var hostHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(HostInfo.brand).font(.headline)
                Spacer()
                Text("v\(model.j2kVersionString)").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(HostInfo.modelIdentifier) · \(HostInfo.systemName) \(HostInfo.systemVersion) · \(HostInfo.ncpu) cores")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Controls

    private var runControls: some View {
        VStack(spacing: 8) {
            HStack {
                Stepper("Runs: \(model.runs)", value: $model.runs, in: 3...11, step: 2)
                    .disabled(isRunning)
                Stepper("Warmups: \(model.warmups)", value: $model.warmups, in: 0...4)
                    .disabled(isRunning)
            }
            HStack {
                Button(action: start) {
                    Label(isRunning ? "Running…" : "Run Benchmark",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                Button(action: prepareShare) {
                    Label("Share JSON", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(isRunning || model.results.isEmpty)
            }
            if model.progressTotal > 0 {
                ProgressView(value: Double(model.progressCompleted),
                             total: Double(model.progressTotal)) {
                    Text(progressLabel).font(.caption)
                }
            }
        }
        .padding()
    }

    private var progressLabel: String {
        switch model.phase {
        case .idle: return "Ready"
        case .warming(let s): return "Warming: \(s)"
        case .encoding(let f): return "Encode · \(f)"
        case .decoding(let f, let mode): return "Decode \(mode) · \(f)"
        case .done: return "Done — \(model.results.count) fixtures"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    // MARK: - Results
    //
    // Layout: one horizontal ScrollView wraps a fixed-width table
    // (fixture column + 4 timing columns). Small phones (iPhone SE)
    // can't fit all columns at once, so the whole table scrolls
    // left/right as a unit while staying vertically scrollable.

    private static let fixtureColumnWidth: CGFloat = 140
    private static let timingColumnWidth: CGFloat = 72
    private static var tableWidth: CGFloat {
        fixtureColumnWidth + timingColumnWidth * 4 + 24
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Median ms per fixture — swipe \u{2190}\u{2192} to see more columns")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    resultsHeader
                    Divider()
                    ForEach(BenchModel.corpus) { fixture in
                        resultRow(fixture)
                        Divider()
                    }
                }
                .frame(width: Self.tableWidth, alignment: .leading)
            }
        }
    }

    private var resultsHeader: some View {
        HStack(spacing: 0) {
            Text("Fixture").bold()
                .frame(width: Self.fixtureColumnWidth, alignment: .leading)
            Text("Encode").bold()
                .frame(width: Self.timingColumnWidth, alignment: .trailing)
            Text("Dec CPU").bold()
                .frame(width: Self.timingColumnWidth, alignment: .trailing)
            Text("Dec GPU").bold()
                .frame(width: Self.timingColumnWidth, alignment: .trailing)
            Text("Dec GPUHT").bold()
                .frame(width: Self.timingColumnWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func resultRow(_ fixture: BenchFixture) -> some View {
        let r = model.results[fixture.id]
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fixture.id).font(.caption.weight(.medium))
                Text("\(fixture.modality) \u{00b7} \(fixture.width)\u{00d7}\(fixture.height)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: Self.fixtureColumnWidth, alignment: .leading)

            ms(r?.encode.median).frame(width: Self.timingColumnWidth, alignment: .trailing)
            ms(r?.decodeCPU.median).frame(width: Self.timingColumnWidth, alignment: .trailing)
            ms(r?.decodeGPU.median).frame(width: Self.timingColumnWidth, alignment: .trailing)
            ms(r?.decodeWithGPUHT.median).frame(width: Self.timingColumnWidth, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func ms(_ value: Double?) -> Text {
        guard let value else { return Text("\u{2014}").foregroundStyle(.tertiary) }
        return Text(String(format: "%.1f", value))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Warm in-process · HT-J2K lossless · median of \(model.runs) after \(model.warmups) warmups")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Send the shared JSON back to the project team for the v10.5 cross-silicon comparison.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Actions

    private func start() {
        isRunning = true
        let runner = BenchRunner(model: model)
        Task {
            await runner.runAll()
            isRunning = false
        }
    }

    private func prepareShare() {
        guard let data = model.encodeAsJSON() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(model.hostJSONFilename)
        try? data.write(to: url, options: .atomic)
        exportURL = url
        #if os(iOS)
        showShareSheet = true
        #else
        macShare(url: url)
        #endif
    }

    #if os(macOS)
    private func macShare(url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow {
            picker.show(
                relativeTo: .zero,
                of: window.contentView ?? NSView(),
                preferredEdge: .minY)
        }
    }
    #endif
}

#if os(iOS)
import UIKit

/// Thin UIViewControllerRepresentable bridge so we can drive the
/// system share sheet from SwiftUI without pulling in a 3rd-party
/// package.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
