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

    private var resultsList: some View {
        List {
            Section {
                resultsHeader
                ForEach(BenchModel.corpus) { fixture in
                    resultRow(fixture)
                }
            } header: {
                Text("Median ms per fixture (lower is better)")
                    .font(.caption2)
            }
        }
        .listStyle(.plain)
    }

    private var resultsHeader: some View {
        HStack {
            Text("Fixture").bold().frame(width: 130, alignment: .leading)
            Spacer()
            Text("Enc").bold().frame(width: 50, alignment: .trailing)
            Text("CPU").bold().frame(width: 50, alignment: .trailing)
            Text("GPU").bold().frame(width: 50, alignment: .trailing)
            Text("GPUHT").bold().frame(width: 60, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func resultRow(_ fixture: BenchFixture) -> some View {
        let r = model.results[fixture.id]
        return HStack {
            VStack(alignment: .leading) {
                Text(fixture.id).font(.caption2)
                Text("\(fixture.modality) · \(fixture.width)×\(fixture.height)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 130, alignment: .leading)
            Spacer()
            ms(r?.encode.median).frame(width: 50, alignment: .trailing)
            ms(r?.decodeCPU.median).frame(width: 50, alignment: .trailing)
            ms(r?.decodeGPU.median).frame(width: 50, alignment: .trailing)
            ms(r?.decodeWithGPUHT.median).frame(width: 60, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
    }

    private func ms(_ value: Double?) -> Text {
        guard let value else { return Text("—").foregroundStyle(.tertiary) }
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
