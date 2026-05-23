//
// FixtureDetailView.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Per-fixture drill-down: a Swift Charts bar chart comparing the
// encode + three decode lanes, a min/median/max table, and the raw
// timing samples. Pure value inputs — renders identically for a live
// in-progress result and a finished saved one.

import SwiftUI
import Charts

/// Navigation route for `FixtureDetailView` — carries everything the
/// detail screen needs so it stays free of `BenchModel`/`BenchStore`
/// and is reachable from both the live Run screen and a saved run.
struct FixtureDetailRoute: Hashable {
    let fixture: BenchFixture
    let result: FixtureResult?
    let runs: Int
    let warmups: Int
}

struct FixtureDetailView: View {
    let fixture: BenchFixture
    let result: FixtureResult?
    let runs: Int
    let warmups: Int

    /// One encode/decode lane, in display order.
    private struct Lane: Identifiable {
        let id = UUID()
        let name: String
        let timing: TimingSamples
        let isDecode: Bool
    }

    private var lanes: [Lane] {
        guard let r = result else { return [] }
        return [
            Lane(name: "Encode", timing: r.encode,          isDecode: false),
            Lane(name: "CPU",    timing: r.decodeCPU,        isDecode: true),
            Lane(name: "GPU",    timing: r.decodeGPU,        isDecode: true),
            Lane(name: "GPU-HT", timing: r.decodeWithGPUHT,  isDecode: true),
        ]
    }

    /// Name of the fastest decode lane (lowest median), for highlight.
    private var fastestDecodeLane: String? {
        lanes
            .filter { $0.isDecode && $0.timing.median != nil }
            .min { ($0.timing.median ?? .infinity) < ($1.timing.median ?? .infinity) }?
            .name
    }

    var body: some View {
        List {
            summarySection
            if result != nil {
                chartSection
                lanesSection
            } else {
                Section {
                    Text("This fixture has not been measured yet.")
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
        Section("Fixture") {
            infoRow("Modality", fixture.modality)
            infoRow("Dimensions", "\(fixture.width) \u{00d7} \(fixture.height)")
            infoRow("Bit depth", "\(fixture.bitDepth)-bit")
            infoRow("Megapixels",
                    String(format: "%.1f MP", Double(fixture.pixels) / 1_000_000))
            if let r = result, r.codestreamBytes > 0 {
                infoRow("Codestream", byteText(r.codestreamBytes))
                infoRow("Compression", compressionRatio(r))
            }
            if let mode = fastestDecodeLane {
                infoRow("Fastest decode", mode, valueColor: .green)
            }
            if let err = result?.error {
                infoRow("Error", err, valueColor: .red)
            }
        }
    }

    private func compressionRatio(_ r: FixtureResult) -> String {
        let raw = fixture.pixels * ((fixture.bitDepth + 7) / 8)
        guard r.codestreamBytes > 0 else { return "\u{2014}" }
        return String(format: "%.2f\u{00d7}", Double(raw) / Double(r.codestreamBytes))
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
                        Text(lane.name)
                            .font(.subheadline.weight(.medium))
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
