//
// InteropView.swift
// J2KSwift
//
// OpenJPEG interoperability comparison screen.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for OpenJPEG interoperability testing.
///
/// Provides side-by-side decode comparison between J2KSwift and OpenJPEG,
/// pixel difference overlay with configurable tolerance, performance
/// comparison bar chart, codestream structure diff tree, and bidirectional
/// encode/decode tests.
struct InteropView: View {
    @State var viewModel: InteropViewModel

    @State private var showDiffOverlay: Bool = false

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
        .navigationTitle("Interoperability")
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                Task { await viewModel.runComparison(session: session) }
            }) {
                Label("Run Comparison", systemImage: "arrow.left.arrow.right")
            }
            .disabled(viewModel.isRunning || viewModel.inputFileURL == nil)

            Toggle("Bidirectional", isOn: $viewModel.isBidirectional)
                .toggleStyle(.switch)
                .help("Test both encode→decode and decode→encode directions")

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
            // File selection
            Text("Input Codestream")
                .font(.headline)

            if let url = viewModel.inputFileURL {
                Label(url.lastPathComponent, systemImage: "doc")
                    .font(.caption)
            } else {
                Text("Drop a J2K/JP2 file here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Tolerance threshold
            Text("Tolerance Threshold")
                .font(.headline)

            HStack {
                Slider(value: Binding(
                    get: { Double(viewModel.toleranceThreshold) },
                    set: { viewModel.toleranceThreshold = Int($0) }
                ), in: 0...10, step: 1)
                Text("\(viewModel.toleranceThreshold)")
                    .monospacedDigit()
                    .frame(width: 24)
            }

            Divider()

            // Performance summary
            if let result = viewModel.comparisonResult {
                performanceSummary(result: result)
            }

            Divider()

            // Results history
            if !viewModel.allResults.isEmpty {
                Text("Results History")
                    .font(.headline)

                ForEach(Array(viewModel.allResults.enumerated()), id: \.offset) { _, result in
                    HStack {
                        Image(systemName: result.withinTolerance ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.withinTolerance ? .green : .red)
                        Text(result.codestreamName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.2f×", result.speedup))
                            .font(.caption.monospacedDigit())
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Performance Summary

    @ViewBuilder
    private func performanceSummary(result: InteropComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Comparison")
                .font(.headline)

            // Bar chart
            VStack(spacing: 4) {
                HStack {
                    Text("J2KSwift")
                        .font(.caption)
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        let maxTime = max(result.j2kSwiftTime, result.openJPEGTime)
                        let width = maxTime > 0 ? CGFloat(result.j2kSwiftTime / maxTime) * geo.size.width : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.blue)
                            .frame(width: width, height: 16)
                    }
                    .frame(height: 16)
                    Text(String(format: "%.1f ms", result.j2kSwiftTime * 1000))
                        .font(.caption.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("OpenJPEG")
                        .font(.caption)
                        .frame(width: 70, alignment: .leading)
                    GeometryReader { geo in
                        let maxTime = max(result.j2kSwiftTime, result.openJPEGTime)
                        let width = maxTime > 0 ? CGFloat(result.openJPEGTime / maxTime) * geo.size.width : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.orange)
                            .frame(width: width, height: 16)
                    }
                    .frame(height: 16)
                    Text(String(format: "%.1f ms", result.openJPEGTime * 1000))
                        .font(.caption.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }
            }

            HStack {
                Text("Speedup:")
                    .font(.caption)
                Text(String(format: "%.2f×", result.speedup))
                    .font(.caption.bold())
                    .foregroundStyle(result.speedup >= 1.0 ? .green : .red)
            }

            HStack {
                Text("Max pixel diff:")
                    .font(.caption)
                Text("\(result.maxPixelDifference)")
                    .font(.caption.bold())
                    .foregroundStyle(result.withinTolerance ? .green : .red)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.diffNodes.isEmpty && viewModel.comparisonResult == nil {
            ContentUnavailableView {
                Label("No Comparison", systemImage: "arrow.left.arrow.right")
            } description: {
                Text("Load a codestream file and run the comparison to see results.")
            }
        } else {
            VSplitView {
                // Side-by-side image comparison area
                imageComparisonArea
                    .frame(minHeight: 200)

                // Codestream structure diff
                codestreamDiffTree
                    .frame(minHeight: 150)
            }
        }
    }

    // MARK: - Image Comparison Area

    @ViewBuilder
    private var imageComparisonArea: some View {
        HStack(spacing: 0) {
            VStack {
                Text("J2KSwift Output")
                    .font(.caption.bold())
                if viewModel.j2kSwiftImageData != nil {
                    Rectangle()
                        .fill(.blue.opacity(0.1))
                        .overlay {
                            Text("Decoded Image")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                }
            }

            Divider()

            VStack {
                Text("OpenJPEG Output")
                    .font(.caption.bold())
                if viewModel.openJPEGImageData != nil {
                    Rectangle()
                        .fill(.orange.opacity(0.1))
                        .overlay {
                            Text("Decoded Image")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                }
            }
        }
        .padding(8)
    }

    // MARK: - Codestream Structure Diff

    @ViewBuilder
    private var codestreamDiffTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Codestream Structure Diff")
                .font(.caption.bold())
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.diffNodes) { node in
                        diffNodeRow(node: node, indent: 0)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func diffNodeRow(node: CodestreamDiffNode, indent: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: node.matches ? "equal.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(node.matches ? .green : .orange)
                    .font(.caption)

                Text(node.name)
                    .font(.caption.monospaced().bold())

                Text(node.j2kSwiftValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, CGFloat(indent * 16))

            ForEach(node.children) { child in
                diffNodeRow(node: child, indent: indent + 1)
            }
        }
    }
}
#endif
