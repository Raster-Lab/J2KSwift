//
// JP3DHistoryView.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// Root of the Volumes tab. Lists every saved JP3D `JP3DBenchRun` so a
// tester runs the 3D bench once and can browse / re-share / explore
// (MPR viewer) without re-paying the wall. Mirrors `HistoryView` for
// the 2D side, but pushes JP3D-specific detail destinations.

import SwiftUI

enum JP3DBenchRoute: Hashable {
    case newRun
}

struct JP3DHistoryView: View {
    @EnvironmentObject private var store: JP3DBenchStore

    var body: some View {
        NavigationStack {
            Group {
                if store.runs.isEmpty {
                    emptyState
                } else {
                    runList
                }
            }
            .navigationTitle("J2K Volumes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: JP3DBenchRoute.newRun) {
                        Label("New 3D Bench", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: JP3DBenchRoute.self) { route in
                switch route {
                case .newRun: JP3DRunView()
                }
            }
            .navigationDestination(for: JP3DBenchRun.self) { run in
                JP3DRunDetailView(run: run)
            }
            .navigationDestination(for: JP3DFixtureDetailRoute.self) { r in
                JP3DFixtureDetailView(
                    fixture: r.fixture,
                    result: r.result,
                    runs: r.runs,
                    warmups: r.warmups)
            }
            #if canImport(UIKit)
            .navigationDestination(for: MPRRoute.self) { r in
                MPRViewerView(fixture: r.fixture)
            }
            #endif
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No 3D benchmarks yet")
                .font(.headline)
            Text("Run the JP3D bench once \u{2014} the result is saved here so "
                 + "you can browse it (and the MPR viewer for each fixture) "
                 + "without re-paying the wall.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            NavigationLink(value: JP3DBenchRoute.newRun) {
                Label("New 3D Bench", systemImage: "play.fill")
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
                Text("\(store.runs.count) saved 3D run\(store.runs.count == 1 ? "" : "s")")
            } footer: {
                Text("Swipe left to delete. Tap to view results, share, "
                     + "or open the MPR viewer for any fixture.")
            }
        }
    }

    private func runRow(_ run: JP3DBenchRun) -> some View {
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
            Text("\(run.host.brand) \u{00b7} \(run.fixtureCount) volume"
                 + "\(run.fixtureCount == 1 ? "" : "s") \u{00b7} J2KSwift v\(run.j2kVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Saved-run detail

/// Read-only view of one persisted `JP3DBenchRun`. Per-fixture
/// checkboxes drive a share selection so the user re-exports any
/// subset later, plus a tap-to-drill row navigates to the per-fixture
/// detail + MPR viewer entry.
struct JP3DRunDetailView: View {
    let run: JP3DBenchRun

    @State private var shareSelection: Set<String>
    @State private var shareItem: ShareItem?
    @EnvironmentObject private var store: JP3DBenchStore

    init(run: JP3DBenchRun) {
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
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
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
                Text("Median ms \u{00b7} tap a row for samples & MPR viewer")
            } footer: {
                Text("Warm in-process \u{00b7} HT-J2K lossless \u{00b7} "
                     + "encode + 3 decode lanes (full / res-1 / ROI 1/4), "
                     + "median of \(run.runs) after \(run.warmups) warmups.")
            }
        }
        .listStyle(.plain)
    }

    private func row(_ result: JP3DFixtureResult) -> some View {
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

            NavigationLink(value: JP3DFixtureDetailRoute(
                fixture: fixture,
                result: result,
                runs: run.runs,
                warmups: run.warmups)) {
                JP3DFixtureRow(fixture: fixture,
                               result: result,
                               status: result.error != nil ? .failed : .done)
            }
        }
    }

    /// Saved runs only store a `JP3DFixtureResult`; rebuild a display
    /// `JP3DFixture` (prefer the live corpus entry, else synthesise
    /// one — `seed` is irrelevant for display).
    private func displayFixture(for result: JP3DFixtureResult) -> JP3DFixture {
        JP3DBenchModel.fixture(id: result.fixture)
            ?? JP3DFixture(id: result.fixture,
                           modality: result.modality,
                           width: result.width,
                           height: result.height,
                           depth: result.depth,
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
        shareItem = ShareItem(url: url)
    }
}

// MARK: - Per-fixture row (3D analogue of FixtureRow)

struct JP3DFixtureRow: View {
    let fixture: JP3DFixture
    let result: JP3DFixtureResult?
    let status: JP3DFixtureStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fixture.label).font(.subheadline.weight(.medium))
                Spacer()
                JP3DStatusBadge(status: status)
            }
            HStack(spacing: 12) {
                Text("\(fixture.width)\u{00d7}\(fixture.height)\u{00d7}\(fixture.depth) \u{00b7} \(fixture.bitDepth)-bit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let r = result {
                    metric("enc", r.encode.median)
                    metric("dec", r.decodeFull.median)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func metric(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(msText(value)) ms")
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

// MARK: - JP3D status badge (3D analogue of StatusBadge)

struct JP3DStatusBadge: View {
    let status: JP3DFixtureStatus

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var text: String {
        switch status {
        case .notSelected: return "Excluded"
        case .notRun:      return "Not run"
        case .running:     return "Running"
        case .done:        return "Done"
        case .failed:      return "Failed"
        }
    }
    private var symbol: String {
        switch status {
        case .notSelected: return "minus.circle"
        case .notRun:      return "circle.dotted"
        case .running:     return "hourglass"
        case .done:        return "checkmark.circle.fill"
        case .failed:      return "exclamationmark.triangle.fill"
        }
    }
    private var tint: Color {
        switch status {
        case .notSelected: return .secondary
        case .notRun:      return .secondary
        case .running:     return .blue
        case .done:        return .green
        case .failed:      return .red
        }
    }
}
