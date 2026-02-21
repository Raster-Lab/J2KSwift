//
// JPIPTestView.swift
// J2KSwift
//
// JPIP streaming test dashboard with progressive image canvas,
// window-of-interest selection, network metrics, and request log.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for JPIP streaming tests.
///
/// Provides a server connection panel, progressive image canvas,
/// window-of-interest selector, network metrics, and a scrollable
/// request log with per-request timing.
struct JPIPTestView: View {
    @State var viewModel: JPIPViewModel

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
        .navigationTitle("JPIP Streaming")
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                Task { await viewModel.connect(session: session) }
            }) {
                Label("Connect", systemImage: "network")
            }
            .disabled(viewModel.sessionStatus == .connected ||
                      viewModel.sessionStatus == .connecting ||
                      viewModel.isStreaming)

            Button(action: {
                viewModel.disconnect()
            }) {
                Label("Disconnect", systemImage: "network.slash")
            }
            .disabled(viewModel.sessionStatus == .disconnected)

            Button(action: {
                Task { await viewModel.requestProgressiveLoad(session: session) }
            }) {
                Label("Load Image", systemImage: "arrow.down.circle")
            }
            .disabled(viewModel.sessionStatus != .connected || viewModel.isStreaming)

            Spacer()

            if viewModel.isStreaming {
                ProgressView(value: viewModel.progress)
                    .frame(width: 120)
            }

            statusBadge

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        let (colour, label): (Color, String) = {
            switch viewModel.sessionStatus {
            case .disconnected: return (.gray, "Off")
            case .connecting:   return (.orange, "…")
            case .connected:    return (.green, "On")
            case .streaming:    return (.blue, "↓")
            case .error:        return (.red, "Err")
            }
        }()
        HStack(spacing: 4) {
            Circle()
                .fill(colour)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colour.opacity(0.15), in: Capsule())
    }

    // MARK: - Control Panel

    @ViewBuilder
    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Server URL
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server URL")
                        .font(.headline)
                    TextField("jpip://…", text: $viewModel.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                }

                Divider()

                // Window-of-interest
                VStack(alignment: .leading, spacing: 6) {
                    Text("Window of Interest")
                        .font(.headline)
                    labeledSlider("X", value: $viewModel.windowX, in: 0...1)
                    labeledSlider("Y", value: $viewModel.windowY, in: 0...1)
                    labeledSlider("W", value: $viewModel.windowWidth, in: 0.1...1)
                    labeledSlider("H", value: $viewModel.windowHeight, in: 0.1...1)
                }

                Divider()

                // Resolution & quality
                VStack(alignment: .leading, spacing: 6) {
                    Text("Request Parameters")
                        .font(.headline)
                    Stepper(
                        "Resolution Level: \(viewModel.currentResolutionLevel)",
                        value: $viewModel.currentResolutionLevel,
                        in: 0...viewModel.maxResolutionLevel
                    )
                    .font(.caption)
                    Text("Quality Layer: \(viewModel.currentQualityLayer) / \(viewModel.maxQualityLayer)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Network metrics
                networkMetricsPanel

                Spacer()

                Button("Clear Log", role: .destructive) {
                    viewModel.clearLog()
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private func labeledSlider(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 14, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Network Metrics Panel

    @ViewBuilder
    private var networkMetricsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Network Metrics")
                .font(.headline)

            metricRow("Bytes Received", value: formatBytes(viewModel.metrics.totalBytesReceived))
            metricRow("Avg Latency", value: String(format: "%.1f ms", viewModel.metrics.averageLatencyMs))
            metricRow("Requests", value: "\(viewModel.metrics.requestCount)")
            metricRow("Duration", value: String(format: "%.1f s", viewModel.metrics.sessionDurationSeconds))
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).fontWeight(.semibold)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
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
        if viewModel.requestLog.isEmpty {
            ContentUnavailableView {
                Label("No Requests Yet", systemImage: "network")
            } description: {
                Text("Connect to a JPIP server and load an image to see the request log.")
            }
        } else {
            VSplitView {
                progressiveCanvas
                    .frame(minHeight: 180)
                requestLogTable
                    .frame(minHeight: 120)
            }
        }
    }

    // MARK: - Progressive Canvas Placeholder

    @ViewBuilder
    private var progressiveCanvas: some View {
        VStack(spacing: 8) {
            Text("Progressive Image Canvas")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.08))

                if viewModel.isStreaming {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Receiving layer \(viewModel.currentQualityLayer) / \(viewModel.maxQualityLayer)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Image rendered progressively as layers arrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("WOI: (\(String(format: "%.2f", viewModel.windowX)), \(String(format: "%.2f", viewModel.windowY))) "
                             + "\(String(format: "%.2f", viewModel.windowWidth))×\(String(format: "%.2f", viewModel.windowHeight))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
    }

    // MARK: - Request Log Table

    @ViewBuilder
    private var requestLogTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Request Log")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            // Header row
            HStack(spacing: 0) {
                Text("Time").font(.caption.bold()).frame(width: 80, alignment: .leading)
                Text("Status").font(.caption.bold()).frame(width: 50, alignment: .center)
                Text("Bytes").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Latency").font(.caption.bold()).frame(width: 80, alignment: .trailing)
                Text("Path").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.requestLog) { request in
                        HStack(spacing: 0) {
                            Text(request.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit())
                                .frame(width: 80, alignment: .leading)
                            Text("\(request.statusCode)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(request.statusCode == 200 ? .green : .red)
                                .frame(width: 50, alignment: .center)
                            Text(formatBytes(request.bytesReceived))
                                .font(.caption.monospacedDigit())
                                .frame(width: 80, alignment: .trailing)
                            Text(String(format: "%.1f ms", request.latencyMs))
                                .font(.caption.monospacedDigit())
                                .frame(width: 80, alignment: .trailing)
                            Text(request.path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 2)
                        Divider()
                    }
                }
            }
        }
    }
}
#endif
