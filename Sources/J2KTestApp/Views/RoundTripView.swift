//
// RoundTripView.swift
// J2KSwift
//
// Round-trip validation screen: encode → decode → compare with PSNR,
// SSIM, MSE metrics, bit-exact lossless badge, and difference image.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Round-Trip View

/// GUI screen for round-trip encode → decode validation.
///
/// Provides a one-click workflow that encodes an input image, decodes
/// it back, and computes PSNR, SSIM, and MSE quality metrics with
/// colour-coded pass/fail thresholds. A bit-exact badge confirms
/// lossless round-trips. A difference image highlights pixel-level
/// discrepancies, and a test image generator creates synthetic inputs.
struct RoundTripView: View {
    /// View model driving this screen.
    @State var viewModel: RoundTripViewModel

    let session: TestSession

    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 260, maxWidth: 320)

            VStack(spacing: 0) {
                toolBar
                Divider()
                mainContent
            }
        }
        .navigationTitle("Round-Trip Validation")
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                Task { await viewModel.runRoundTrip(session: session) }
            }) {
                Label("Run Round-Trip", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(viewModel.isRunning || viewModel.encodeViewModel.inputImageData == nil)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Encode → Decode → Compare (⌘↵)")

            Spacer()

            Toggle(isOn: $viewModel.showDifferenceImage) {
                Label("Difference", systemImage: "minus.square.on.square")
            }
            .toggleStyle(.button)
            .disabled(viewModel.roundTrippedImageData == nil)
            .help("Show the pixel-level difference image")

            if let metrics = viewModel.metrics {
                passFailBadge(metrics)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Progress
            if viewModel.isRunning || viewModel.progress > 0 {
                ProgressIndicatorView(
                    overallProgress: viewModel.progress,
                    stages: [],
                    statusMessage: viewModel.statusMessage
                )
                Divider()
            }

            // Image area
            if viewModel.originalImageData != nil || viewModel.roundTrippedImageData != nil {
                if viewModel.showDifferenceImage {
                    differenceImagePanel
                } else {
                    ImageComparisonView(
                        originalData: viewModel.originalImageData,
                        processedData: viewModel.roundTrippedImageData
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label("No Images", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Generate or load an image and press Run Round-Trip.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Metrics panel
            if let metrics = viewModel.metrics {
                Divider()
                metricsPanel(metrics)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Metrics Panel

    @ViewBuilder
    private func metricsPanel(_ metrics: RoundTripMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                // Bit-exact badge
                if metrics.isBitExact {
                    Label("Bit-Exact Lossless", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                metricCard(
                    label: "PSNR",
                    value: metrics.psnr.isInfinite ? "∞ dB" : String(format: "%.1f dB", metrics.psnr),
                    passes: metrics.psnrPasses || metrics.isBitExact,
                    threshold: "≥ \(Int(RoundTripMetrics.psnrPassThreshold)) dB"
                )

                metricCard(
                    label: "SSIM",
                    value: String(format: "%.4f", metrics.ssim),
                    passes: metrics.ssimPasses || metrics.isBitExact,
                    threshold: "≥ \(String(format: "%.2f", RoundTripMetrics.ssimPassThreshold))"
                )

                metricCard(
                    label: "MSE",
                    value: String(format: "%.4f", metrics.mse),
                    passes: metrics.mse < 10.0 || metrics.isBitExact,
                    threshold: "< 10.0"
                )

                Spacer()
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// A single quality metric card with colour-coded pass/fail.
    @ViewBuilder
    private func metricCard(label: String, value: String, passes: Bool, threshold: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(passes ? .green : .red)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(threshold)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background((passes ? Color.green : Color.red).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Pass/Fail Badge (Toolbar)

    @ViewBuilder
    private func passFailBadge(_ metrics: RoundTripMetrics) -> some View {
        let passes = metrics.passes || metrics.isBitExact
        Label(passes ? "Pass" : "Fail",
              systemImage: passes ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(passes ? .green : .red)
    }

    // MARK: - Difference Image Panel

    @ViewBuilder
    private var differenceImagePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pixel Difference")
                    .font(.headline)
                Spacer()
                Text("Bright pixels indicate discrepancies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ImagePreviewView(
                imageData: viewModel.roundTrippedImageData,
                title: "Difference Image"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Left Panel

    @ViewBuilder
    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Test image generator
                GroupBox("Test Image Generator") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Type", selection: $viewModel.selectedTestImageType) {
                            ForEach(RoundTripViewModel.TestImageType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.radioGroup)

                        Button(action: { viewModel.generateTestImage() }) {
                            Label("Generate", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Encoding configuration (uses the encodeViewModel config)
                GroupBox("Encoding Preset") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(EncodeConfiguration.Preset.allCases, id: \.rawValue) { preset in
                            Button(preset.rawValue) {
                                viewModel.encodeViewModel.applyPreset(preset)
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .font(.caption)
                        }
                    }
                }

                // Current config summary
                GroupBox("Configuration") {
                    let config = viewModel.encodeViewModel.configuration
                    VStack(alignment: .leading, spacing: 4) {
                        configRow(label: "Quality", value: String(format: "%.2f", config.quality))
                        configRow(label: "Wavelet", value: config.waveletType.rawValue)
                        configRow(label: "Tile", value: "\(config.tileWidth)×\(config.tileHeight)")
                        configRow(label: "HTJ2K", value: config.htj2kEnabled ? "On" : "Off")
                        configRow(label: "MCT", value: config.mctEnabled ? "On" : "Off")
                    }
                }

                // Metric thresholds reference
                GroupBox("Pass Thresholds") {
                    VStack(alignment: .leading, spacing: 4) {
                        configRow(label: "PSNR", value: "≥ \(Int(RoundTripMetrics.psnrPassThreshold)) dB")
                        configRow(label: "SSIM", value: "≥ \(String(format: "%.2f", RoundTripMetrics.ssimPassThreshold))")
                        configRow(label: "MSE", value: "< 10.0")
                    }
                }

                // Status
                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }
}
#endif
