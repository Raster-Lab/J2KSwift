//
// ConformanceView.swift
// J2KSwift
//
// Conformance matrix dashboard for ISO/IEC 15444-4 testing.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for ISO/IEC 15444-4 conformance testing.
///
/// Displays a conformance matrix grid with rows for each requirement
/// and columns for standard parts (1, 2, 3/10, 15). Cells are colour-
/// coded green (pass), red (fail), or grey (skip). Users can filter by
/// part, expand requirement details, run all tests, and export reports.
struct ConformanceView: View {
    @State var viewModel: ConformanceViewModel

    let session: TestSession

    var body: some View {
        HSplitView {
            controlPanel
                .frame(minWidth: 260, maxWidth: 320)

            VStack(spacing: 0) {
                toolBar
                Divider()
                mainContent
            }
        }
        .navigationTitle("Conformance")
        .onAppear {
            if viewModel.requirements.isEmpty {
                viewModel.loadDefaultRequirements()
            }
        }
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                Task { await viewModel.runAllTests(session: session) }
            }) {
                Label("Run All Conformance Tests", systemImage: "play.fill")
            }
            .disabled(viewModel.isRunning)

            Spacer()

            if viewModel.isRunning {
                ProgressView(value: viewModel.progress)
                    .frame(width: 120)
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Control Panel

    @ViewBuilder
    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary banner
            if let report = viewModel.report {
                summaryBanner(report: report)
            }

            Divider()

            // Part tab selector
            Text("Filter by Part")
                .font(.headline)

            Picker("Part", selection: $viewModel.selectedPart) {
                Text("All Parts").tag(ConformancePart?.none)
                ForEach(ConformancePart.allCases) { part in
                    Text(part.rawValue).tag(ConformancePart?.some(part))
                }
            }
            .pickerStyle(.segmented)

            Divider()

            // Export section
            Text("Export Report")
                .font(.headline)

            Picker("Format", selection: $viewModel.exportFormat) {
                ForEach(ConformanceExportFormat.allCases, id: \.rawValue) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Button(action: {
                _ = viewModel.exportReport()
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.report == nil)

            Spacer()
        }
        .padding()
    }

    // MARK: - Summary Banner

    @ViewBuilder
    private func summaryBanner(report: ConformanceReport) -> some View {
        VStack(spacing: 8) {
            Text(report.summaryBanner)
                .font(.title3)
                .fontWeight(.semibold)

            ProgressView(value: report.passRate, total: 100)
                .tint(report.failedTests == 0 ? .green : .orange)

            HStack(spacing: 16) {
                Label("\(report.passedTests)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("\(report.failedTests)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Label("\(report.skippedTests)", systemImage: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Text(String(format: "%.3fs", report.duration))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Main Content (Matrix)

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.filteredRequirements.isEmpty {
            ContentUnavailableView {
                Label("No Requirements", systemImage: "checkmark.shield")
            } description: {
                Text("Load the default requirement set or run conformance tests.")
            }
        } else {
            conformanceMatrix
        }
    }

    @ViewBuilder
    private var conformanceMatrix: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header row
                matrixHeaderRow
                Divider()

                // Requirement rows
                ForEach(viewModel.filteredRequirements) { requirement in
                    matrixRow(for: requirement)
                    Divider()
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var matrixHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Requirement")
                .font(.caption.bold())
                .frame(width: 80, alignment: .leading)
            Text("Description")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(ConformancePart.allCases) { part in
                Text(part.rawValue)
                    .font(.caption.bold())
                    .frame(width: 60)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func matrixRow(for requirement: ConformanceRequirement) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(requirement.requirementId)
                    .font(.caption.monospaced())
                    .frame(width: 80, alignment: .leading)

                Text(requirement.description)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(ConformancePart.allCases) { part in
                    cellView(status: requirement.results[part])
                        .frame(width: 60)
                }

                Button(action: {
                    withAnimation {
                        if viewModel.expandedRequirementId == requirement.id {
                            viewModel.expandedRequirementId = nil
                        } else {
                            viewModel.expandedRequirementId = requirement.id
                        }
                    }
                }) {
                    Image(systemName: viewModel.expandedRequirementId == requirement.id
                          ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)

            // Expanded detail log
            if viewModel.expandedRequirementId == requirement.id {
                Text(requirement.detailLog.isEmpty ? "No detail log available." : requirement.detailLog)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
            }
        }
    }

    @ViewBuilder
    private func cellView(status: ConformanceCellStatus?) -> some View {
        switch status {
        case .pass:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .skip:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        case nil:
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
        }
    }
}
#endif
