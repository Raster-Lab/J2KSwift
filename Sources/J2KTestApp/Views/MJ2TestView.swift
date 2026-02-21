//
// MJ2TestView.swift
// J2KSwift
//
// Motion JPEG 2000 testing dashboard: frame sequence loader, playback
// controls, per-frame quality inspector, and encoding configuration.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for Motion JPEG 2000 testing.
///
/// Provides a frame sequence loader, playback controls (play/pause/stop,
/// step forward/backward, frame slider), a per-frame quality inspector,
/// and uniform or per-frame encoding configuration.
struct MJ2TestView: View {
    @State var viewModel: MJ2TestViewModel

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
        .navigationTitle("Motion JPEG 2000")
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                Task { await viewModel.loadSequence(session: session) }
            }) {
                Label("Load Sequence", systemImage: "film.stack")
            }
            .disabled(viewModel.isRunning)

            Button(action: {
                viewModel.clearFrames()
            }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(viewModel.frames.isEmpty || viewModel.isRunning)

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Encoding configuration
                VStack(alignment: .leading, spacing: 6) {
                    Text("Encoding Configuration")
                        .font(.headline)

                    Toggle("Uniform Settings", isOn: $viewModel.useUniformEncoding)
                        .font(.caption)

                    if viewModel.useUniformEncoding {
                        HStack {
                            Text("Quality")
                                .font(.caption)
                            Slider(value: $viewModel.uniformQuality, in: 0...1)
                            Text(String(format: "%.2f", viewModel.uniformQuality))
                                .font(.caption.monospacedDigit())
                                .frame(width: 36)
                        }
                    } else {
                        Text("Per-frame settings — click a frame in the timeline to configure.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Frame Rate")
                            .font(.caption)
                        Spacer()
                        TextField("fps", value: $viewModel.frameRate, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .font(.caption.monospacedDigit())
                    }
                }

                Divider()

                // Sequence summary
                if !viewModel.frames.isEmpty {
                    sequenceSummaryPanel
                    Divider()
                }

                // Per-frame quality inspector
                if let frame = viewModel.currentFrame {
                    frameInspectorPanel(frame: frame)
                    Divider()
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Sequence Summary Panel

    @ViewBuilder
    private var sequenceSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sequence Summary")
                .font(.headline)

            summaryRow("Frames", value: "\(viewModel.frames.count)")
            summaryRow("Duration", value: String(format: "%.2f s", viewModel.totalDurationSeconds))
            summaryRow("Frame Rate", value: String(format: "%.0f fps", viewModel.frameRate))

            if !viewModel.frames.isEmpty {
                let avgPSNR = viewModel.frames.map(\.psnr).reduce(0, +) / Double(viewModel.frames.count)
                let avgSSIM = viewModel.frames.map(\.ssim).reduce(0, +) / Double(viewModel.frames.count)
                summaryRow("Avg PSNR", value: String(format: "%.1f dB", avgPSNR))
                summaryRow("Avg SSIM", value: String(format: "%.4f", avgSSIM))
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).fontWeight(.semibold)
        }
    }

    // MARK: - Frame Inspector Panel

    @ViewBuilder
    private func frameInspectorPanel(frame: MJ2Frame) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Frame \(frame.frameNumber) Inspector")
                .font(.headline)

            summaryRow("Timestamp", value: String(format: "%.3f s", frame.timestampSeconds))
            summaryRow("Size", value: "\(frame.width)×\(frame.height)")
            summaryRow("Compressed", value: formatBytes(frame.compressedSizeBytes))
            summaryRow("PSNR", value: String(format: "%.1f dB", frame.psnr))
            summaryRow("SSIM", value: String(format: "%.4f", frame.ssim))
            summaryRow("Decode Time", value: String(format: "%.2f ms", frame.decodeTimeMs))
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
        if viewModel.frames.isEmpty {
            ContentUnavailableView {
                Label("No Frame Sequence", systemImage: "film.stack")
            } description: {
                Text("Click Load Sequence to open an MJ2 file or generate a test sequence.")
            }
        } else {
            VSplitView {
                framePreviewArea
                    .frame(minHeight: 200)
                frameTimeline
                    .frame(minHeight: 100)
            }
        }
    }

    // MARK: - Frame Preview Area

    @ViewBuilder
    private var framePreviewArea: some View {
        VStack(spacing: 8) {
            // Full-size decode placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.08))

                if let frame = viewModel.currentFrame {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Frame \(frame.frameNumber) of \(viewModel.frames.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.3f s  •  PSNR %.1f dB  •  SSIM %.4f",
                                    frame.timestampSeconds, frame.psnr, frame.ssim))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)

            // Playback controls
            playbackControls
                .padding(.bottom, 8)
        }
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private var playbackControls: some View {
        VStack(spacing: 6) {
            // Frame scrubber
            if !viewModel.frames.isEmpty {
                HStack {
                    Text("0:00")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.currentFrameIndex) },
                            set: { viewModel.currentFrameIndex = Int($0) }
                        ),
                        in: 0...Double(max(viewModel.frames.count - 1, 1)),
                        step: 1
                    )
                    Text(String(format: "0:%02d", Int(viewModel.totalDurationSeconds)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            // Transport buttons
            HStack(spacing: 20) {
                Button(action: viewModel.stop) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.playbackState == .stopped)

                Button(action: viewModel.stepBackward) {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.currentFrameIndex == 0)

                Button(action: viewModel.togglePlayback) {
                    Image(systemName: viewModel.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.frames.isEmpty)

                Button(action: viewModel.stepForward) {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.frames.isEmpty || viewModel.currentFrameIndex >= viewModel.frames.count - 1)

                Spacer()

                Text(playbackStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private var playbackStateLabel: String {
        switch viewModel.playbackState {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    // MARK: - Frame Timeline

    @ViewBuilder
    private var frameTimeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Frame Timeline")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.frames.count) frames · \(String(format: "%.0f", viewModel.frameRate)) fps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(viewModel.frames) { frame in
                        let isSelected = frame.frameNumber == (viewModel.currentFrame?.frameNumber ?? -1)
                        VStack(spacing: 2) {
                            if isSelected {
                                Triangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 5)
                            } else {
                                Spacer().frame(height: 5)
                            }

                            RoundedRectangle(cornerRadius: 2)
                                .fill(psnrColour(frame.psnr).gradient)
                                .frame(
                                    width: 14,
                                    height: max(4, CGFloat((frame.psnr - 30) / 20) * 50)
                                )
                        }
                        .onTapGesture {
                            viewModel.currentFrameIndex = frame.frameNumber - 1
                        }
                    }
                }
                .padding(.horizontal)
                .frame(height: 70)
            }

            // Legend
            HStack(spacing: 8) {
                colorLegendItem(color: .green, label: "≥45 dB")
                colorLegendItem(color: .yellow, label: "40–45 dB")
                colorLegendItem(color: .orange, label: "<40 dB")
                Spacer()
                Text("Bar height = PSNR")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func psnrColour(_ psnr: Double) -> Color {
        if psnr >= 45 { return .green }
        if psnr >= 40 { return .yellow }
        return .orange
    }

    private func colorLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Triangle Shape Helper

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
#endif
