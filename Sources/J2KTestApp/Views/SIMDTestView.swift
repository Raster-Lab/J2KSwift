//
// SIMDTestView.swift
// J2KSwift
//
// SIMD vectorisation testing dashboard with utilisation gauges.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for SIMD operation testing and verification.
///
/// Displays ARM Neon and Intel SSE/AVX operation test lists,
/// a SIMD utilisation percentage gauge (target ≥85%), and
/// per-operation speedup charts comparing SIMD vs scalar timing.
struct SIMDTestView: View {
    @State var viewModel: SIMDTestViewModel

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
        .navigationTitle("SIMD Testing")
        .onAppear {
            viewModel.detectPlatform()
        }
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                Task { await viewModel.runAllTests(session: session) }
            }) {
                Label("Run All SIMD Tests", systemImage: "play.fill")
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

            platformBadge

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Platform Badge

    @ViewBuilder
    private var platformBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.caption)
            Text(platformName)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15), in: Capsule())
    }

    private var platformName: String {
        if viewModel.isARM { return "ARM Neon" }
        if viewModel.isX86 { return "x86 SSE/AVX" }
        return "Generic"
    }

    // MARK: - Control Panel

    @ViewBuilder
    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Utilisation gauge
                utilisationGauge

                Divider()

                // Platform info
                Text("Platform")
                    .font(.headline)

                HStack {
                    Text("Architecture:")
                        .font(.caption)
                    Spacer()
                    Text(platformName)
                        .font(.caption.monospaced())
                }

                HStack {
                    Text("ARM Neon:")
                        .font(.caption)
                    Spacer()
                    Image(systemName: viewModel.isARM
                          ? "checkmark.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(viewModel.isARM ? .green : .secondary)
                }

                HStack {
                    Text("x86 SSE/AVX:")
                        .font(.caption)
                    Spacer()
                    Image(systemName: viewModel.isX86
                          ? "checkmark.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(viewModel.isX86 ? .green : .secondary)
                }

                Divider()

                // Operation list
                Text("Operations")
                    .font(.headline)

                ForEach(SIMDOperationType.allCases) { op in
                    HStack {
                        Image(systemName: resultIcon(for: op))
                            .foregroundStyle(resultColor(for: op))
                            .font(.caption)
                        Text(op.rawValue)
                            .font(.caption)
                        Spacer()
                        if let result = viewModel.results.first(where: { $0.operation == op }) {
                            Text(String(format: "%.1f×", result.speedup))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(result.speedup > 1 ? .green : .red)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private func resultIcon(for op: SIMDOperationType) -> String {
        guard let result = viewModel.results.first(where: { $0.operation == op }) else {
            return "circle"
        }
        return result.outputsMatch ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func resultColor(for op: SIMDOperationType) -> Color {
        guard let result = viewModel.results.first(where: { $0.operation == op }) else {
            return .secondary
        }
        return result.outputsMatch ? .green : .red
    }

    // MARK: - Utilisation Gauge

    @ViewBuilder
    private var utilisationGauge: some View {
        VStack(spacing: 8) {
            Text("SIMD Utilisation")
                .font(.headline)

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: viewModel.utilisationPercentage / 100)
                    .stroke(
                        utilisationColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(String(format: "%.0f%%", viewModel.utilisationPercentage))
                        .font(.title2.monospacedDigit())
                        .fontWeight(.bold)
                    Text("Target: \(Int(viewModel.targetUtilisation))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            if viewModel.utilisationPercentage >= viewModel.targetUtilisation {
                Label("Target Met", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if !viewModel.results.isEmpty {
                Label("Below Target", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var utilisationColor: Color {
        if viewModel.utilisationPercentage >= viewModel.targetUtilisation {
            return .green
        } else if viewModel.utilisationPercentage >= viewModel.targetUtilisation * 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.results.isEmpty {
            ContentUnavailableView {
                Label("No SIMD Test Results", systemImage: "cpu")
            } description: {
                Text("Click Run All SIMD Tests to compare vectorised vs scalar operations.")
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    speedupChart
                    Divider()
                    resultsTable
                }
                .padding()
            }
        }
    }

    // MARK: - Speedup Chart

    @ViewBuilder
    private var speedupChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIMD vs Scalar Speedup")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(viewModel.results) { result in
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f×", result.speedup))
                            .font(.caption2.monospacedDigit())

                        RoundedRectangle(cornerRadius: 4)
                            .fill(result.speedup >= 2
                                  ? Color.green.gradient : Color.orange.gradient)
                            .frame(width: 36, height: max(4, CGFloat(result.speedup) * 25))

                        Text(result.operation.rawValue)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
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
                Text("Operation").font(.caption.bold()).frame(width: 140, alignment: .leading)
                Text("SIMD (ms)").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Scalar (ms)").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Speedup").font(.caption.bold()).frame(width: 70, alignment: .trailing)
                Text("Match").font(.caption.bold()).frame(width: 50, alignment: .center)
                Text("Platform").font(.caption.bold()).frame(width: 90, alignment: .trailing)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)

            Divider()

            ForEach(viewModel.results) { result in
                HStack(spacing: 0) {
                    Text(result.operation.rawValue)
                        .font(.caption)
                        .frame(width: 140, alignment: .leading)
                    Text(String(format: "%.2f", result.simdTimeMs))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.2f", result.scalarTimeMs))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.1f×", result.speedup))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(result.speedup > 1 ? .green : .red)
                        .frame(width: 70, alignment: .trailing)
                    Image(systemName: result.outputsMatch
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.outputsMatch ? .green : .red)
                        .frame(width: 50)
                    Text(result.platform)
                        .font(.caption2)
                        .frame(width: 90, alignment: .trailing)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                Divider()
            }
        }
    }
}
#endif
