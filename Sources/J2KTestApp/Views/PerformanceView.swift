//
// PerformanceView.swift
// J2KSwift
//
// Performance benchmarking dashboard with live charts and regression detection.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for interactive performance benchmarking.
///
/// Provides benchmark configuration, live throughput/latency bar charts,
/// memory usage gauges, historical comparison, and regression detection
/// with green/amber/red badges. Results can be exported as CSV or JSON.
struct PerformanceView: View {
    @State var viewModel: PerformanceViewModel
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
        .navigationTitle("Performance")
    }

    // MARK: - Tool Bar
    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                Task { await viewModel.runBenchmark(session: session) }
            }) {
                Label("Run Benchmark", systemImage: "play.fill")
            }
            .disabled(viewModel.isRunning)

            Button(action: { viewModel.clearResults() }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(viewModel.isRunning)

            Spacer()

            if viewModel.isRunning {
                ProgressView(value: viewModel.progress)
                    .frame(width: 120)
            }

            regressionBadge

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Regression Badge
    @ViewBuilder
    private var regressionBadge: some View {
        // Green/amber/red badge based on regression status
        HStack(spacing: 4) {
            Circle()
                .fill(regressionColor)
                .frame(width: 10, height: 10)
            Text(viewModel.regressionStatus.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(regressionColor.opacity(0.15), in: Capsule())
    }

    private var regressionColor: Color {
        switch viewModel.regressionStatus {
        case .green: return .green
        case .amber: return .orange
        case .red: return .red
        }
    }

    // MARK: - Control Panel
    @ViewBuilder
    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Memory usage gauges
                memoryGauges

                Divider()

                // Image size selection
                Text("Image Sizes")
                    .font(.headline)

                ForEach(BenchmarkImageSizeChoice.allCases) { size in
                    Toggle(size.rawValue, isOn: Binding(
                        get: { viewModel.selectedSizes.contains(size) },
                        set: { isOn in
                            if isOn { viewModel.selectedSizes.insert(size) }
                            else { viewModel.selectedSizes.remove(size) }
                        }
                    ))
                    .font(.caption)
                }

                Divider()

                // Coding mode selection
                Text("Coding Modes")
                    .font(.headline)

                ForEach(BenchmarkCodingModeChoice.allCases) { mode in
                    Toggle(mode.rawValue, isOn: Binding(
                        get: { viewModel.selectedModes.contains(mode) },
                        set: { isOn in
                            if isOn { viewModel.selectedModes.insert(mode) }
                            else { viewModel.selectedModes.remove(mode) }
                        }
                    ))
                    .font(.caption)
                }

                Divider()

                // Iteration and warm-up
                Stepper("Iterations: \(viewModel.iterationCount)", value: $viewModel.iterationCount, in: 1...100)
                Stepper("Warm-up: \(viewModel.warmUpRounds)", value: $viewModel.warmUpRounds, in: 0...10)

                Divider()

                // Export
                Text("Export Results")
                    .font(.headline)

                Picker("Format", selection: $viewModel.exportFormat) {
                    Text("CSV").tag("CSV")
                    Text("JSON").tag("JSON")
                }
                .pickerStyle(.segmented)

                Button(action: {
                    _ = viewModel.exportResults()
                }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.currentResults.isEmpty)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Memory Gauges
    @ViewBuilder
    private var memoryGauges: some View {
        VStack(spacing: 8) {
            Text("Memory Usage")
                .font(.headline)

            HStack(spacing: 16) {
                memoryGauge(title: "Peak", bytes: viewModel.peakMemoryBytes)
                memoryGauge(title: "Current", bytes: viewModel.currentMemoryBytes)
            }

            HStack {
                Text("Allocations:")
                    .font(.caption)
                Spacer()
                Text("\(viewModel.allocationCount)")
                    .font(.caption.monospacedDigit())
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func memoryGauge(title: String, bytes: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatBytes(bytes))
                .font(.caption.monospacedDigit())
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return "\(bytes) B"
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        if viewModel.currentResults.isEmpty {
            ContentUnavailableView {
                Label("No Benchmark Results", systemImage: "gauge.with.dots.needle.67percent")
            } description: {
                Text("Configure benchmark parameters and click Run Benchmark.")
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    throughputChart
                    Divider()
                    latencyChart
                    Divider()
                    resultsTable
                }
                .padding()
            }
        }
    }

    // MARK: - Throughput Chart
    @ViewBuilder
    private var throughputChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Throughput (MP/s)")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(viewModel.currentResults) { result in
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", result.throughputMPPerSecond))
                            .font(.caption2.monospacedDigit())

                        RoundedRectangle(cornerRadius: 4)
                            .fill(.blue.gradient)
                            .frame(width: 36, height: max(4, CGFloat(result.throughputMPPerSecond) * 8))

                        Text(result.imageSize.rawValue)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(width: 50)
                    }
                }
            }
            .frame(height: 200, alignment: .bottom)
        }
    }

    // MARK: - Latency Chart
    @ViewBuilder
    private var latencyChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latency (ms)")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(viewModel.currentResults) { result in
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", result.latencyMs))
                            .font(.caption2.monospacedDigit())

                        RoundedRectangle(cornerRadius: 4)
                            .fill(.orange.gradient)
                            .frame(width: 36, height: max(4, CGFloat(result.latencyMs) * 2))

                        Text(result.codingMode.rawValue)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(width: 50)
                    }
                }
            }
            .frame(height: 200, alignment: .bottom)
        }
    }

    // MARK: - Results Table
    @ViewBuilder
    private var resultsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detailed Results")
                .font(.headline)

            // Header
            HStack(spacing: 0) {
                Text("Size").font(.caption.bold()).frame(width: 80, alignment: .leading)
                Text("Mode").font(.caption.bold()).frame(width: 100, alignment: .leading)
                Text("Throughput").font(.caption.bold()).frame(width: 90, alignment: .trailing)
                Text("Latency").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Peak Mem").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Allocs").font(.caption.bold()).frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)

            Divider()

            ForEach(viewModel.currentResults) { result in
                HStack(spacing: 0) {
                    Text(result.imageSize.rawValue)
                        .font(.caption.monospaced())
                        .frame(width: 80, alignment: .leading)
                    Text(result.codingMode.rawValue)
                        .font(.caption)
                        .frame(width: 100, alignment: .leading)
                    Text(String(format: "%.2f MP/s", result.throughputMPPerSecond))
                        .font(.caption.monospacedDigit())
                        .frame(width: 90, alignment: .trailing)
                    Text(String(format: "%.1f ms", result.latencyMs))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text(formatBytes(result.peakMemoryBytes))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text("\(result.allocationCount)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                Divider()
            }
        }
    }
}
#endif
