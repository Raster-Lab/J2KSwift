//
// VolumetricTestView.swift
// J2KSwift
//
// JP3D volumetric testing dashboard: volume loader, slice navigator,
// 3D wavelet parameters, per-slice quality metrics, and comparison view.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for JP3D volumetric testing.
///
/// Provides volume loader controls, a slice navigator with axial/coronal/sagittal
/// plane selection, 3D wavelet parameter panel, per-slice quality metrics table,
/// and a comparison view showing original vs decoded slices with difference overlay.
struct VolumetricTestView: View {
    @State var viewModel: VolumetricTestViewModel

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
        .navigationTitle("JP3D Volumetric Testing")
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                Task { await viewModel.runVolumetricTest(session: session) }
            }) {
                Label("Run Test", systemImage: "play.fill")
            }
            .disabled(viewModel.isRunning)

            Button(action: {
                viewModel.clearResults()
            }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(viewModel.sliceMetrics.isEmpty || viewModel.isRunning)

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
                // Plane selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anatomical Plane")
                        .font(.headline)
                    Picker("Plane", selection: $viewModel.selectedPlane) {
                        ForEach(VolumetricPlane.allCases, id: \.self) { plane in
                            Text(plane.rawValue).tag(plane)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                // Slice navigator
                VStack(alignment: .leading, spacing: 6) {
                    Text("Slice Navigator")
                        .font(.headline)
                    HStack {
                        Text("Slice")
                            .font(.caption)
                        Spacer()
                        Text("\(viewModel.currentSliceIndex + 1) / \(viewModel.totalSlices)")
                            .font(.caption.monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.currentSliceIndex) },
                            set: { viewModel.currentSliceIndex = Int($0) }
                        ),
                        in: 0...Double(max(viewModel.totalSlices - 1, 1)),
                        step: 1
                    )

                    HStack(spacing: 8) {
                        Button(action: { viewModel.currentSliceIndex = max(viewModel.currentSliceIndex - 1, 0) }) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.currentSliceIndex == 0)

                        Spacer()

                        Button(action: {
                            viewModel.currentSliceIndex = min(viewModel.currentSliceIndex + 1, viewModel.totalSlices - 1)
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.currentSliceIndex >= viewModel.totalSlices - 1)
                    }
                }

                Divider()

                // Wavelet parameters
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wavelet Parameters")
                        .font(.headline)

                    Stepper(
                        "Z-axis Levels: \(viewModel.zDecompositionLevels)",
                        value: $viewModel.zDecompositionLevels,
                        in: 1...6
                    )
                    .font(.caption)

                    Picker("Wavelet", selection: $viewModel.waveletType) {
                        Text("5/3 (lossless)").tag("5/3 (lossless)")
                        Text("9/7 (lossy)").tag("9/7 (lossy)")
                        Text("Haar").tag("Haar")
                    }
                    .pickerStyle(.radioGroup)
                    .font(.caption)
                }

                Divider()

                // Difference overlay toggle
                Toggle("Show Difference Overlay", isOn: $viewModel.showDifferenceImage)
                    .font(.caption)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.sliceMetrics.isEmpty {
            ContentUnavailableView {
                Label("No Volumetric Data", systemImage: "cube.transparent")
            } description: {
                Text("Click Run Test to encode and decode a simulated volume and inspect per-slice metrics.")
            }
        } else {
            VSplitView {
                sliceComparison
                    .frame(minHeight: 180)
                qualityMetricsTable
                    .frame(minHeight: 120)
            }
        }
    }

    // MARK: - Slice Comparison View

    @ViewBuilder
    private var sliceComparison: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Slice Comparison — \(viewModel.selectedPlane.rawValue) \(viewModel.currentSliceIndex + 1)")
                    .font(.headline)
                Spacer()

                if let slice = currentDisplaySlice {
                    Label(String(format: "%.1f dB", slice.psnr), systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(String(format: "%.4f", slice.ssim), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack(spacing: 12) {
                slicePlaceholder(label: "Original")
                slicePlaceholder(label: viewModel.showDifferenceImage ? "Difference" : "Decoded")
            }
            .padding(.horizontal)
        }
    }

    private func slicePlaceholder(label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.08))
            VStack(spacing: 4) {
                Image(systemName: label == "Difference" ? "minus.square" : "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var currentDisplaySlice: VolumeSlice? {
        let matches = viewModel.sliceMetrics.filter {
            $0.plane == viewModel.selectedPlane && $0.index == viewModel.currentSliceIndex
        }
        return matches.first
    }

    // MARK: - Quality Metrics Table

    @ViewBuilder
    private var qualityMetricsTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Per-Slice Quality Metrics")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            metricsHeaderRow

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.sliceMetrics) { slice in
                        metricsRow(for: slice)
                        Divider()
                    }
                }
            }
        }
    }

    private var metricsHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Slice").font(.caption.bold()).frame(width: 50, alignment: .center)
            Text("Plane").font(.caption.bold()).frame(width: 70, alignment: .leading)
            Text("PSNR (dB)").font(.caption.bold()).frame(width: 90, alignment: .trailing)
            Text("SSIM").font(.caption.bold()).frame(width: 80, alignment: .trailing)
            Text("Decode (ms)").font(.caption.bold()).frame(width: 100, alignment: .trailing)
            Text("Size").font(.caption.bold()).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal)
    }

    private func metricsRow(for slice: VolumeSlice) -> some View {
        HStack(spacing: 0) {
            Text("\(slice.index + 1)")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .center)
            Text(slice.plane.rawValue)
                .font(.caption)
                .frame(width: 70, alignment: .leading)
            Text(String(format: "%.1f", slice.psnr))
                .font(.caption.monospacedDigit())
                .foregroundColor(slice.psnr >= 40 ? Color.primary : Color.orange)
                .frame(width: 90, alignment: .trailing)
            Text(String(format: "%.4f", slice.ssim))
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Text(String(format: "%.2f", slice.decodeTimeMs))
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .trailing)
            Text("\(slice.width)×\(slice.height)")
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }
}
#endif
