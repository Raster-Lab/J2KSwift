//
// JP3DFixtureDetailView.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// Per-JP3D-fixture drill-down: dimensions + compression, a Swift
// Charts bar chart over the 4 lanes (encode + decodeFull + decodeRes1
// + decodeROIQuarter), a min/median/max table with samples, plus a
// "Open in MPR Viewer" affordance that decodes the fixture's
// codestream and pushes the 3-plane viewer.
//
// The MPR viewer is the demo-grade verification surface for the
// v10.18 partial-resolution / ROI ports — eyes-on confirmation that
// the planned true-selective decode is producing the right voxels
// next to numbers showing it's also faster.

import SwiftUI
import Charts

struct JP3DFixtureDetailRoute: Hashable {
    let fixture: JP3DFixture
    let result: JP3DFixtureResult?
    let runs: Int
    let warmups: Int
}

struct JP3DFixtureDetailView: View {
    let fixture: JP3DFixture
    let result: JP3DFixtureResult?
    let runs: Int
    let warmups: Int

    private struct Lane: Identifiable {
        let id = UUID()
        let name: String
        let timing: TimingSamples
        let isDecode: Bool
    }

    private var lanes: [Lane] {
        guard let r = result else { return [] }
        return [
            Lane(name: "Encode",   timing: r.encode,           isDecode: false),
            Lane(name: "Full",     timing: r.decodeFull,       isDecode: true),
            Lane(name: "Res-1",    timing: r.decodeRes1,       isDecode: true),
            Lane(name: "ROI 1/4",  timing: r.decodeROIQuarter, isDecode: true),
        ]
    }

    private var fastestDecodeLane: String? {
        lanes
            .filter { $0.isDecode && $0.timing.median != nil }
            .min { ($0.timing.median ?? .infinity) < ($1.timing.median ?? .infinity) }?
            .name
    }

    var body: some View {
        List {
            summarySection
            mprSection
            if result != nil {
                chartSection
                lanesSection
            } else {
                Section {
                    Text("This volume has not been measured yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(fixture.label)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section("Volume") {
            infoRow("Modality", fixture.modality)
            infoRow("Dimensions",
                    "\(fixture.width) \u{00d7} \(fixture.height) \u{00d7} \(fixture.depth)")
            infoRow("Bit depth", "\(fixture.bitDepth)-bit")
            infoRow("Voxels",
                    String(format: "%.1f MV", Double(fixture.voxels) / 1_000_000))
            if let r = result, r.codestreamBytes > 0 {
                infoRow("Codestream", byteText(r.codestreamBytes))
                infoRow("Raw size",   byteText(r.rawBytes))
                infoRow("Compression",
                        r.compressionRatio.map { String(format: "%.2f\u{00d7}", $0) } ?? "\u{2014}")
            }
            if let mode = fastestDecodeLane {
                infoRow("Fastest decode", mode, valueColor: .green)
            }
            if let err = result?.error {
                infoRow("Error", err, valueColor: .red)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String,
                         valueColor: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    // MARK: - MPR viewer entry

    private var mprSection: some View {
        Section {
            NavigationLink(value: MPRRoute(fixture: fixture)) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open in MPR Viewer")
                            .font(.subheadline.weight(.medium))
                        Text("Decode this volume and inspect axial / "
                             + "sagittal / coronal slices with crosshair.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cube.transparent")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        Section("Median timing (ms)") {
            Chart(lanes) { lane in
                BarMark(
                    x: .value("Lane", lane.name),
                    y: .value("ms", lane.timing.median ?? 0)
                )
                .foregroundStyle(barColor(for: lane))
                .annotation(position: .top) {
                    if lane.timing.median != nil {
                        Text(msText(lane.timing.median))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxisLabel("ms")
            .frame(height: 200)
            .padding(.vertical, 4)
        }
    }

    private func barColor(for lane: Lane) -> Color {
        if !lane.isDecode { return .orange }
        return lane.name == fastestDecodeLane ? .green : .blue
    }

    // MARK: - Per-lane detail

    private var lanesSection: some View {
        Section("Samples — median of \(runs) after \(warmups) warmups") {
            ForEach(lanes) { lane in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(lane.name).font(.subheadline.weight(.medium))
                        if lane.name == fastestDecodeLane {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Text("\(msText(lane.timing.median)) ms")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    HStack(spacing: 12) {
                        Text("min \(msText(lane.timing.min))")
                        Text("max \(msText(lane.timing.max))")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    if !lane.timing.samples.isEmpty {
                        Text(lane.timing.samples
                            .map { String(format: "%.1f", $0) }
                            .joined(separator: "  "))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// Navigation route for the MPR viewer. Carries just the fixture so
/// the viewer re-synthesises + encodes + decodes lazily on push (no
/// state coupling to a particular run).
struct MPRRoute: Hashable {
    let fixture: JP3DFixture
}
