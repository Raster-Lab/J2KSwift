//
// ResultsTableView.swift
// J2KSwift
//
// Results table with sortable columns for test results.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Sort Column

/// Columns available for sorting in the results table.
enum ResultsSortColumn: String {
    case testName = "Test Name"
    case status = "Status"
    case duration = "Duration"
    case category = "Category"
}

// MARK: - Results Table View

/// Results table displaying test outcomes with sortable columns.
///
/// Shows test name, status (colour-coded), duration, and optional
/// metrics. Supports sorting by clicking column headers and selecting
/// individual results for detail inspection.
struct ResultsTableView: View {
    /// The test results to display.
    let results: [TestResult]

    /// Binding to the selected result.
    @Binding var selectedResult: TestResult?

    /// Current sort column.
    @State private var sortColumn: ResultsSortColumn = .testName
    /// Current sort direction.
    @State private var sortAscending: Bool = true

    /// Sorted results based on current sort column and direction.
    private var sortedResults: [TestResult] {
        let sorted: [TestResult]
        switch sortColumn {
        case .testName:
            sorted = results.sorted { $0.testName < $1.testName }
        case .status:
            sorted = results.sorted { $0.status.rawValue < $1.status.rawValue }
        case .duration:
            sorted = results.sorted { $0.duration < $1.duration }
        case .category:
            sorted = results.sorted { $0.category.rawValue < $1.category.rawValue }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                headerButton(title: "Test Name", column: .testName, width: 200)
                headerButton(title: "Status", column: .status, width: 80)
                headerButton(title: "Duration", column: .duration, width: 100)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Result rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedResults) { result in
                        resultRow(result)
                            .onTapGesture {
                                selectedResult = result
                            }
                    }
                }
            }
        }
    }

    /// Creates a sortable column header button.
    @ViewBuilder
    private func headerButton(title: String, column: ResultsSortColumn, width: CGFloat) -> some View {
        Button(action: {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: .leading)
    }

    /// Creates a row for a single test result.
    @ViewBuilder
    private func resultRow(_ result: TestResult) -> some View {
        HStack(spacing: 0) {
            Text(result.testName)
                .font(.body)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)

            statusBadge(result.status)
                .frame(width: 80)

            Text(String(format: "%.1f ms", result.duration * 1000))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)

            Spacer()

            if !result.message.isEmpty {
                Text(result.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(selectedResult?.id == result.id ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    /// Creates a colour-coded status badge.
    @ViewBuilder
    private func statusBadge(_ status: TestStatus) -> some View {
        Text(status.rawValue)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColour(status).opacity(0.2))
            .foregroundStyle(statusColour(status))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Returns the colour for a test status.
    private func statusColour(_ status: TestStatus) -> Color {
        switch status {
        case .passed: return .green
        case .failed: return .red
        case .skipped: return .gray
        case .error: return .orange
        case .running: return .blue
        case .pending: return .secondary
        }
    }
}
#endif
