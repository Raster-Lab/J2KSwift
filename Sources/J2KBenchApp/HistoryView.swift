//
// HistoryView.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// App root. Owns the single `NavigationStack` and lists every saved
// `BenchRun` so a tester runs the bench once and can browse / re-share
// it forever. Also hosts `RunDetailView`, the read-only view of one
// saved run with its own per-fixture share selection.

import SwiftUI

/// Pushed destinations that aren't a value model.
enum BenchRoute: Hashable {
    case newRun
}

struct HistoryView: View {
    @EnvironmentObject private var store: BenchStore

    var body: some View {
        NavigationStack {
            Group {
                if store.runs.isEmpty {
                    emptyState
                } else {
                    runList
                }
            }
            .navigationTitle("J2K Bench")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: BenchRoute.newRun) {
                        Label("New Benchmark", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: BenchRoute.self) { route in
                switch route {
                case .newRun: RunView()
                }
            }
            .navigationDestination(for: BenchRun.self) { run in
                RunDetailView(run: run)
            }
            .navigationDestination(for: FixtureDetailRoute.self) { r in
                FixtureDetailView(fixture: r.fixture, result: r.result,
                                  runs: r.runs, warmups: r.warmups)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No benchmarks yet")
                .font(.headline)
            Text("Run the bench once \u{2014} the result is saved here so "
                 + "you never have to re-run to view it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            NavigationLink(value: BenchRoute.newRun) {
                Label("New Benchmark", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Run list

    private var runList: some View {
        List {
            Section {
                ForEach(store.runs) { run in
                    NavigationLink(value: run) { runRow(run) }
                }
                .onDelete { offsets in
                    for index in offsets { store.delete(store.runs[index]) }
                }
            } header: {
                Text("\(store.runs.count) saved run\(store.runs.count == 1 ? "" : "s")")
            } footer: {
                Text("Swipe a run left to delete. Tap to view results "
                     + "and share any subset of fixtures.")
            }
        }
    }

    private func runRow(_ run: BenchRun) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(run.title).font(.subheadline.weight(.semibold))
                Spacer()
                if run.hasFailures {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text("\(run.host.brand) \u{00b7} \(run.fixtureCount) fixture"
                 + "\(run.fixtureCount == 1 ? "" : "s") \u{00b7} J2KSwift v\(run.j2kVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Saved-run detail

/// Read-only view of one persisted `BenchRun`. Per-fixture checkboxes
/// drive a share selection so the user re-exports any subset later.
struct RunDetailView: View {
    let run: BenchRun

    @State private var shareSelection: Set<String>
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @EnvironmentObject private var store: BenchStore

    init(run: BenchRun) {
        self.run = run
        _shareSelection = State(initialValue: Set(run.results.map(\.fixture)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HostHeader(brand: run.host.brand,
                       detail: hostDetail,
                       version: run.j2kVersion)
            Divider()
            shareBar
            Divider()
            fixtureList
        }
        .navigationTitle(run.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL { ShareSheet(activityItems: [url]) }
        }
        #endif
    }

    private var hostDetail: String {
        "\(run.host.modelIdentifier) \u{00b7} \(run.host.systemName) "
        + "\(run.host.systemVersion) \u{00b7} \(run.host.ncpu) cores"
    }

    // MARK: Share bar

    private var shareBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(shareSelection.count) of \(run.results.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(allSelected ? "Select none" : "Select all") {
                    if allSelected { shareSelection.removeAll() }
                    else { shareSelection = Set(run.results.map(\.fixture)) }
                }
                .font(.caption)
            }
            Button(action: prepareShare) {
                Label("Share Selected", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(shareSelection.isEmpty)
        }
        .padding()
    }

    private var allSelected: Bool {
        shareSelection.count == run.results.count
    }

    // MARK: Fixture list

    private var fixtureList: some View {
        List {
            Section {
                ForEach(run.results) { result in
                    row(result)
                }
            } header: {
                Text("Median ms \u{00b7} tap a row for samples & chart")
            } footer: {
                Text("Warm in-process \u{00b7} HT-J2K lossless \u{00b7} median "
                     + "of \(run.runs) after \(run.warmups) warmups.")
            }
        }
        .listStyle(.plain)
    }

    private func row(_ result: FixtureResult) -> some View {
        let fixture = displayFixture(for: result)
        let selected = shareSelection.contains(result.fixture)
        return HStack(spacing: 12) {
            Button {
                if selected { shareSelection.remove(result.fixture) }
                else { shareSelection.insert(result.fixture) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            NavigationLink(value: FixtureDetailRoute(
                fixture: fixture,
                result: result,
                runs: run.runs,
                warmups: run.warmups)) {
                FixtureRow(fixture: fixture,
                           result: result,
                           status: result.error != nil ? .failed : .done)
            }
        }
    }

    /// A saved run only stores `FixtureResult`; rebuild a display
    /// `BenchFixture` (prefer the live corpus entry, else synthesise
    /// one — `seed` is irrelevant for display).
    private func displayFixture(for result: FixtureResult) -> BenchFixture {
        BenchModel.fixture(id: result.fixture)
            ?? BenchFixture(id: result.fixture,
                            modality: result.modality,
                            width: result.width,
                            height: result.height,
                            bitDepth: result.bitDepth,
                            seed: 0)
    }

    // MARK: Actions

    private func prepareShare() {
        guard let data = store.exportData(run: run,
                                          fixtureIDs: shareSelection) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(store.exportFilename(for: run))
        try? data.write(to: url, options: .atomic)
        exportURL = url
        #if os(iOS)
        showShareSheet = true
        #endif
    }
}
