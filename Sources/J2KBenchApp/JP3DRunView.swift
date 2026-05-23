//
// JP3DRunView.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// New 3D benchmark screen. Tick which JP3D fixtures to measure, run,
// watch per-fixture progress, then share the selected subset.
// Mirrors `RunView` for the 2D side.

import SwiftUI

struct JP3DRunView: View {
    @EnvironmentObject private var store: JP3DBenchStore
    @StateObject private var model = JP3DBenchModel()

    @State private var isRunning = false
    @State private var completedRun: JP3DBenchRun?
    @State private var shareItem: ShareItem?

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
        .navigationTitle("New 3D Bench")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
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
                Text("\(model.selectedFixtures.count) of \(JP3DBenchModel.corpus.count) selected")
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
        case .done:                    return "Done \u{2014} \(model.results.count) volumes"
        case .failed(let m):           return "Failed: \(m)"
        }
    }

    private func label(_ id: String) -> String {
        JP3DBenchModel.fixture(id: id)?.label ?? id
    }

    // MARK: - Fixture list

    private var fixtureList: some View {
        List {
            Section {
                ForEach(JP3DBenchModel.corpus) { fixture in
                    row(fixture)
                }
            } header: {
                Text("Check to include \u{00b7} tap a row for detail")
            } footer: {
                Text("Selected volumes run, then export. The 512\u{00d7}512\u{00d7}64 "
                     + "CT-large fixture takes the longest \u{2014} ~10-15 s/lane.")
            }
        }
        .listStyle(.plain)
    }

    private func row(_ fixture: JP3DFixture) -> some View {
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

            NavigationLink(value: JP3DFixtureDetailRoute(
                fixture: fixture,
                result: model.results[fixture.id],
                runs: model.runs,
                warmups: model.warmups)) {
                JP3DFixtureRow(fixture: fixture,
                               result: model.results[fixture.id],
                               status: model.status(for: fixture))
            }
        }
    }

    // MARK: - Actions

    private func start() {
        isRunning = true
        completedRun = nil
        let runner = JP3DBenchRunner(model: model, store: store)
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
        shareItem = ShareItem(url: url)
    }
}
