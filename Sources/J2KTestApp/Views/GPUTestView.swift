//
// GPUTestView.swift
// J2KSwift
//
// GPU acceleration testing dashboard with Metal pipeline tests.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for GPU acceleration testing.
///
/// Displays Metal pipeline test controls, GPU vs CPU comparison table,
/// shader compilation status, GPU memory monitor, and visual output
/// comparison between GPU-computed and CPU-computed results.
struct GPUTestView: View {
    @State var viewModel: GPUTestViewModel

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
        .navigationTitle("GPU Testing")
        .onAppear {
            viewModel.checkMetalAvailability()
        }
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                Task { await viewModel.runGPUTest(session: session) }
            }) {
                Label("Run All GPU Tests", systemImage: "play.fill")
            }
            .disabled(viewModel.isRunning || !viewModel.isMetalAvailable)

            Button(action: {
                Task { await viewModel.runSingleOperation(session: session) }
            }) {
                Label("Run Selected", systemImage: "play")
            }
            .disabled(viewModel.isRunning || !viewModel.isMetalAvailable)

            Spacer()

            if viewModel.isRunning {
                ProgressView(value: viewModel.progress)
                    .frame(width: 120)
            }

            metalAvailabilityBadge

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Metal Availability Badge

    @ViewBuilder
    private var metalAvailabilityBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(viewModel.isMetalAvailable ? .green : .red)
                .frame(width: 10, height: 10)
            Text(viewModel.isMetalAvailable ? "Metal" : "No Metal")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (viewModel.isMetalAvailable ? Color.green : Color.red).opacity(0.15),
            in: Capsule()
        )
    }

    // MARK: - Control Panel

    @ViewBuilder
    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // GPU Memory Monitor
                gpuMemoryMonitor

                Divider()

                // Operation selector
                Text("Select Operation")
                    .font(.headline)

                Picker("Operation", selection: $viewModel.selectedOperation) {
                    ForEach(GPUOperation.allCases) { op in
                        Text(op.rawValue).tag(op)
                    }
                }
                .pickerStyle(.radioGroup)

                Divider()

                // Shader compilation status
                Text("Shader Status")
                    .font(.headline)

                if viewModel.shaders.isEmpty {
                    Text("Run GPU tests to compile shaders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.shaders) { shader in
                        HStack {
                            Image(systemName: shader.isCompiled
                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(shader.isCompiled ? .green : .red)
                                .font(.caption)

                            VStack(alignment: .leading) {
                                Text(shader.shaderName)
                                    .font(.caption)
                                Text(String(format: "%.1f ms", shader.compileTimeMs))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(shader.status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - GPU Memory Monitor

    @ViewBuilder
    private var gpuMemoryMonitor: some View {
        VStack(spacing: 8) {
            Text("GPU Memory")
                .font(.headline)

            HStack {
                Text("Buffer Pool:")
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", viewModel.bufferPoolUtilisation * 100))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
            }

            ProgressView(value: viewModel.bufferPoolUtilisation)
                .tint(viewModel.bufferPoolUtilisation > 0.9 ? .red
                      : viewModel.bufferPoolUtilisation > 0.7 ? .orange : .green)

            HStack {
                Text("Peak Usage:")
                    .font(.caption)
                Spacer()
                Text(formatBytes(viewModel.peakGPUMemoryBytes))
                    .font(.caption.monospacedDigit())
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
        if viewModel.results.isEmpty {
            ContentUnavailableView {
                Label("No GPU Test Results", systemImage: "gpu")
            } description: {
                Text("Select an operation and click Run to compare GPU vs CPU performance.")
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    comparisonTable
                    Divider()
                    speedupChart
                }
                .padding()
            }
        }
    }

    // MARK: - GPU vs CPU Comparison Table

    @ViewBuilder
    private var comparisonTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GPU vs CPU Comparison")
                .font(.headline)

            // Header row
            HStack(spacing: 0) {
                Text("Operation").font(.caption.bold()).frame(width: 130, alignment: .leading)
                Text("GPU (ms)").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("CPU (ms)").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Speedup").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Match").font(.caption.bold()).frame(width: 60, alignment: .center)
                Text("GPU Mem").font(.caption.bold()).frame(width: 80, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)

            Divider()

            ForEach(viewModel.results) { result in
                HStack(spacing: 0) {
                    Text(result.operation.rawValue)
                        .font(.caption)
                        .frame(width: 130, alignment: .leading)
                    Text(String(format: "%.2f", result.gpuTimeMs))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.2f", result.cpuTimeMs))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.1f×", result.speedupFactor))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(result.speedupFactor > 1 ? .green : .red)
                        .frame(width: 80, alignment: .trailing)
                    Image(systemName: result.outputsMatch
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.outputsMatch ? .green : .red)
                        .frame(width: 60)
                    Text(formatBytes(result.gpuMemoryBytes))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                Divider()
            }
        }
    }

    // MARK: - Speedup Chart

    @ViewBuilder
    private var speedupChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GPU Speedup Factor")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(viewModel.results) { result in
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f×", result.speedupFactor))
                            .font(.caption2.monospacedDigit())

                        RoundedRectangle(cornerRadius: 4)
                            .fill(result.speedupFactor > 1
                                  ? Color.green.gradient : Color.red.gradient)
                            .frame(width: 44, height: max(4, CGFloat(result.speedupFactor) * 30))

                        Text(result.operation.rawValue)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 60)
                    }
                }
            }
            .frame(height: 200, alignment: .bottom)
        }
    }
}
#endif
