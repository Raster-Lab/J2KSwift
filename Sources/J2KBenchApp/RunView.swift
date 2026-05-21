//
// RunView.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// The "New Benchmark" screen. The user ticks which fixtures to measure,
// taps "Run Selected", watches per-fixture progress, then shares the
// selected subset as canonical JSON. One checkbox set drives both the
// run and the share — pick once, run what you need, send what you want.

import SwiftUI

struct RunView: View {
    @EnvironmentObject private var store: BenchStore
    @StateObject private var model = BenchModel()

    @State private var isRunning = false
    @State private var completedRun: BenchRun?
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HostHeader(brand: HostInfo.brand,
                       detail: hostDetail,
                       version: model.j2kVersionString)
            Divider()
            controls
            Divider()
            fixtureList
        }
        .navigationTitle("New Benchmark")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL { ShareSheet(activityItems: [url]) }
        }
        #endif
    }

    private var hostDetail: String {
        "\(HostInfo.modelIdentifier) \u{00b7} \(HostInfo.systemName) "
        + "\(HostInfo.systemVersion) \u{00b7} \(HostInfo.ncpu) cores"
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Stepper("Runs: \(model.runs)", value: $model.runs, in: 3...11, step: 2)
                Stepper("Warmups: \(model.warmups)", value: $model.warmups, in: 0...4)
            }
            .disabled(isRunning)

            HStack {
                Text("\(model.selectedFixtures.count) of \(BenchModel.corpus.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.allSelected ? "Select none" : "Select all") {
                    if model.allSelected { model.selectNone() } else { model.selectAll() }
                }
                .font(.caption)
                .disabled(isRunning)
            }

            HStack {
                Button(action: start) {
                    Label(isRunning ? "Running\u{2026}" : "Run Selected",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || model.selectedFixtures.isEmpty)

                if model.completed {
                    Button(action: prepareShare) {
                        Label("Share Selected", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning || shareableCount == 0)
                }
            }

            if model.progressTotal > 0 {
                ProgressView(value: Double(model.progressCompleted),
                             total: Double(model.progressTotal)) {
                    Text(progressText).font(.caption)
                }
            }
        }
        .padding()
    }

    private var shareableCount: Int {
        guard let run = completedRun else { return 0 }
        return run.results.filter { model.selectedFixtures.contains($0.fixture) }.count
    }

    private var progressText: String {
        switch model.phase {
        case .idle:                    return "Ready"
        case .warming(let s):          return "Warming: \(s)"
        case .encoding(let id):        return "Encoding \u{00b7} \(label(id))"
        case .decoding(let id, let m): return "Decoding \(m) \u{00b7} \(label(id))"
        case .done:                    return "Done \u{2014} \(model.results.count) fixtures"
        case .failed(let m):           return "Failed: \(m)"
        }
    }

    private func label(_ id: String) -> String {
        BenchModel.fixture(id: id)?.label ?? id
    }

    // MARK: - Fixture list

    private var fixtureList: some View {
        List {
            Section {
                ForEach(BenchModel.corpus) { fixture in
                    row(fixture)
                }
            } header: {
                Text("Check to include \u{00b7} tap a row for detail")
            } footer: {
                Text("Selected fixtures run, then export. Larger "
                     + "mammography-class fixtures take the longest.")
            }
        }
        .listStyle(.plain)
    }

    private func row(_ fixture: BenchFixture) -> some View {
        let selected = model.selectedFixtures.contains(fixture.id)
        return HStack(spacing: 12) {
            Button {
                model.toggle(fixture.id)
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)

            NavigationLink(value: FixtureDetailRoute(
                fixture: fixture,
                result: model.results[fixture.id],
                runs: model.runs,
                warmups: model.warmups)) {
                FixtureRow(fixture: fixture,
                           result: model.results[fixture.id],
                           status: model.status(for: fixture))
            }
        }
    }

    // MARK: - Actions

    private func start() {
        isRunning = true
        completedRun = nil
        let runner = BenchRunner(model: model, store: store)
        Task {
            let run = await runner.run(fixtures: model.selectedFixtures)
            completedRun = run
            isRunning = false
        }
    }

    private func prepareShare() {
        guard let run = completedRun,
              let data = store.exportData(run: run,
                                          fixtureIDs: model.selectedFixtures)
        else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(store.exportFilename(for: run))
        try? data.write(to: url, options: .atomic)
        exportURL = url
        #if os(iOS)
        showShareSheet = true
        #endif
    }
}
