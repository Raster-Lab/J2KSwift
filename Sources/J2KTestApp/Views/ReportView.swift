//
// ReportView.swift
// J2KSwift
//
// Reporting dashboard with summary, trend chart, coverage heatmap, and export.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// Reporting dashboard showing summary stats, trend chart, coverage heatmap, and export.
struct ReportView: View {
    @State var viewModel: ReportViewModel
    let session: TestSession

    var body: some View {
        HSplitView {
            // Left: Controls panel
            controlPanel
                .frame(minWidth: 220, maxWidth: 260)

            // Right: Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection
                    Divider()
                    trendSection
                    Divider()
                    heatmapSection
                }
                .padding()
            }
        }
        .navigationTitle("Report")
        .toolbar { toolbarContent }
        .task {
            await viewModel.loadTrend(session: session)
            viewModel.loadCoverageGrid()
        }
    }

    // MARK: - Control Panel

    @ViewBuilder
    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export")
                .font(.headline)

            Picker("Format", selection: $viewModel.exportFormat) {
                ForEach(ReportExportFormat.allCases, id: \.self) { fmt in
                    Text(fmt.rawValue).tag(fmt)
                }
            }
            .pickerStyle(.radioGroup)

            Button(action: {
                Task {
                    _ = await viewModel.exportReport(to: "test_report.\(viewModel.exportFormat.rawValue.lowercased())")
                }
            }) {
                Label("Export Report", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isExporting)
            .buttonStyle(.borderedProminent)

            if let path = viewModel.lastExportPath {
                Text("Exported to:\n\(path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Summary Section

    @ViewBuilder
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                summaryCard(title: "Total", value: "\(viewModel.trendPoints.last?.totalTests ?? 0)", color: .blue)
                summaryCard(title: "Passed", value: "\(viewModel.trendPoints.last?.passedTests ?? 0)", color: .green)
                summaryCard(title: "Pass Rate", value: String(format: "%.0f%%", (viewModel.trendPoints.last?.passRate ?? 0) * 100), color: .teal)
            }
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Trend Section

    @ViewBuilder
    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pass Rate Trend")
                .font(.title2)
                .fontWeight(.semibold)

            if viewModel.trendPoints.isEmpty {
                Text("No trend data available.")
                    .foregroundStyle(.secondary)
            } else {
                trendChart
                    .frame(height: 140)
            }
        }
    }

    @ViewBuilder
    private var trendChart: some View {
        GeometryReader { geo in
            let points = viewModel.trendPoints
            let maxRate = points.map(\.passRate).max() ?? 1.0
            let minRate = max(0, (points.map(\.passRate).min() ?? 0) - 0.05)
            let range = max(maxRate - minRate, 0.01)
            let w = geo.size.width
            let h = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w

            ZStack(alignment: .bottomLeading) {
                // Grid lines
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    let y = h - CGFloat((level - minRate) / range) * h
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }

                // Line
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - CGFloat((pt.passRate - minRate) / range) * h
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.teal, lineWidth: 2)

                // Dots
                ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                    let x = CGFloat(i) * step
                    let y = h - CGFloat((pt.passRate - minRate) / range) * h
                    Circle()
                        .fill(Color.teal)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
        }
    }

    // MARK: - Heatmap Section

    @ViewBuilder
    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coverage Heatmap")
                .font(.title2)
                .fontWeight(.semibold)

            if viewModel.coverageGrid.isEmpty {
                Text("No coverage data available.")
                    .foregroundStyle(.secondary)
            } else {
                heatmapGrid
            }
        }
    }

    @ViewBuilder
    private var heatmapGrid: some View {
        let parts = Array(Set(viewModel.coverageGrid.map(\.part))).sorted()
        let sections = Array(Set(viewModel.coverageGrid.map(\.section))).sorted()

        VStack(alignment: .leading, spacing: 4) {
            // Column headers
            HStack(spacing: 4) {
                Text("").frame(width: 80)
                ForEach(sections, id: \.self) { section in
                    Text(section)
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }

            ForEach(parts, id: \.self) { part in
                HStack(spacing: 4) {
                    Text(part)
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)
                    ForEach(sections, id: \.self) { section in
                        let cell = viewModel.coverageGrid.first {
                            $0.part == part && $0.section == section
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(coverageColor(cell?.coverageLevel ?? 0))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .overlay(
                                Text("\(cell?.testCount ?? 0)")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                            )
                    }
                }
            }

            // Legend
            HStack(spacing: 8) {
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(coverageColor(level))
                            .frame(width: 14, height: 14)
                        Text(level == 0 ? "None" : level == 1.0 ? "Full" : "\(Int(level * 100))%")
                            .font(.caption2)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func coverageColor(_ level: Double) -> Color {
        switch level {
        case 0..<0.25: return .red.opacity(0.6)
        case 0.25..<0.5: return .orange.opacity(0.7)
        case 0.5..<0.75: return .yellow.opacity(0.7)
        case 0.75..<1.0: return .green.opacity(0.6)
        default: return .green.opacity(0.9)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: {
                Task {
                    await viewModel.loadTrend(session: session)
                    viewModel.loadCoverageGrid()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh report data")
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}
#endif
