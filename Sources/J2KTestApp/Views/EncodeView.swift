//
// EncodeView.swift
// J2KSwift
//
// Encoding GUI screen with drag-and-drop input, configuration panel,
// presets, real-time progress, output inspection, side-by-side
// comparison, and batch encoding.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Encode View

/// GUI screen for testing JPEG 2000 encoding.
///
/// Provides drag-and-drop image input, a configuration panel, preset
/// buttons, a real-time progress bar with per-stage breakdown, and an
/// output panel showing file size, compression ratio, and encoding time.
/// A side-by-side split view lets users compare multiple configurations,
/// and a batch panel encodes a whole folder of images at once.
struct EncodeView: View {
    /// View model driving this screen.
    @State var viewModel: EncodeViewModel

    /// Whether the batch encoding sheet is presented.
    @State private var showBatchSheet: Bool = false

    /// The active tab in the main area.
    @State private var selectedTab: EncodeTab = .single

    let session: TestSession

    var body: some View {
        HSplitView {
            configurationPanel
                .frame(minWidth: 260, maxWidth: 320)

            VStack(spacing: 0) {
                tabBar
                Divider()
                tabContent
            }
        }
        .navigationTitle("Encode")
    }

    // MARK: - Tab Bar

    private enum EncodeTab: String, CaseIterable {
        case single = "Single"
        case compare = "Compare"
        case batch = "Batch"
    }

    @ViewBuilder
    private var tabBar: some View {
        HStack {
            Picker("View", selection: $selectedTab) {
                ForEach(EncodeTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .padding(.horizontal)

            Spacer()

            Button(action: {
                Task { await viewModel.encode(session: session) }
            }) {
                Label("Encode", systemImage: "arrow.up.doc")
            }
            .disabled(viewModel.isEncoding || viewModel.inputImageData == nil)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Encode the selected image (⌘↵)")
            .padding(.trailing)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .single:
            singleTab
        case .compare:
            compareTab
        case .batch:
            batchTab
        }
    }

    // MARK: - Single Tab

    @ViewBuilder
    private var singleTab: some View {
        VStack(spacing: 0) {
            inputDropZone
                .frame(minHeight: 160)

            Divider()

            if viewModel.isEncoding || viewModel.progress > 0 {
                ProgressIndicatorView(
                    overallProgress: viewModel.progress,
                    stages: viewModel.stageProgress,
                    statusMessage: viewModel.statusMessage
                )
            }

            if viewModel.lastResult != nil {
                outputPanel
            }

            if let originalData = viewModel.inputImageData, viewModel.outputData != nil {
                Divider()
                ImageComparisonView(
                    originalData: originalData,
                    processedData: viewModel.outputData
                )
                .frame(minHeight: 200)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Compare Tab

    @ViewBuilder
    private var compareTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Side-by-Side Configuration Comparison")
                    .font(.headline)
                    .padding(.horizontal)
                Spacer()
                Button(action: {
                    viewModel.addComparisonConfiguration(viewModel.configuration)
                }) {
                    Label("Add Current Config", systemImage: "plus")
                }
                .padding(.trailing)
            }
            .padding(.top, 8)

            if viewModel.comparisonConfigurations.isEmpty {
                ContentUnavailableView {
                    Label("No Configurations", systemImage: "square.split.2x1")
                } description: {
                    Text("Add the current configuration to start comparing encoding outputs.")
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(viewModel.comparisonConfigurations.enumerated()), id: \.offset) { index, config in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Config \(index + 1)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Button(action: {
                                        viewModel.removeComparisonConfiguration(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                configSummary(config)

                                ImagePreviewView(imageData: viewModel.outputData, title: "Output")
                            }
                            .padding()
                            .frame(minWidth: 300)

                            if index < viewModel.comparisonConfigurations.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Batch Tab

    @ViewBuilder
    private var batchTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Batch Encoding")
                    .font(.headline)
                Spacer()
                Button(action: {
                    // In a real app this would open NSOpenPanel for folder selection.
                    // Here we populate a placeholder list for demonstration.
                    let placeholders = (1...3).map { i in
                        URL(fileURLWithPath: "/tmp/image\(i).png")
                    }
                    viewModel.setBatchInputURLs(placeholders)
                }) {
                    Label("Select Folder…", systemImage: "folder")
                }
                Button(action: {
                    Task { await viewModel.encodeBatch(session: session) }
                }) {
                    Label("Encode All", systemImage: "play.fill")
                }
                .disabled(viewModel.isEncoding || viewModel.batchInputURLs.isEmpty)
            }
            .padding()

            Divider()

            if viewModel.batchInputURLs.isEmpty {
                ContentUnavailableView {
                    Label("No Images Selected", systemImage: "folder.badge.plus")
                } description: {
                    Text("Select a folder of images to encode them all with the current configuration.")
                }
            } else {
                // Input list
                List(viewModel.batchInputURLs, id: \.absoluteString) { url in
                    Text(url.lastPathComponent)
                        .font(.body)
                }
                .frame(minHeight: 100, maxHeight: 180)

                Divider()

                // Batch results table
                if !viewModel.batchResults.isEmpty {
                    batchResultsTable
                }

                if viewModel.isEncoding {
                    ProgressIndicatorView(
                        overallProgress: viewModel.progress,
                        stages: [],
                        statusMessage: viewModel.statusMessage
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Batch Results Table

    @ViewBuilder
    private var batchResultsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Batch Results")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            // Header
            HStack(spacing: 0) {
                Text("File").font(.caption).fontWeight(.semibold).frame(width: 180, alignment: .leading)
                Text("Input").font(.caption).fontWeight(.semibold).frame(width: 80, alignment: .trailing)
                Text("Encoded").font(.caption).fontWeight(.semibold).frame(width: 80, alignment: .trailing)
                Text("Ratio").font(.caption).fontWeight(.semibold).frame(width: 70, alignment: .trailing)
                Text("Time").font(.caption).fontWeight(.semibold).frame(width: 80, alignment: .trailing)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.batchResults, id: \.inputFileName) { result in
                        HStack(spacing: 0) {
                            Text(result.inputFileName)
                                .font(.body).lineLimit(1)
                                .frame(width: 180, alignment: .leading)
                            Text(formatBytes(result.inputSize))
                                .font(.body).monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                            Text(formatBytes(result.encodedSize))
                                .font(.body).monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                            Text(String(format: "%.2f:1", result.compressionRatio))
                                .font(.body).monospacedDigit()
                                .frame(width: 70, alignment: .trailing)
                            Text(String(format: "%.1f ms", result.encodingTime * 1000))
                                .font(.body).monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: 200)
        }
    }

    // MARK: - Input Drop Zone

    @ViewBuilder
    private var inputDropZone: some View {
        VStack(spacing: 8) {
            if let imageData = viewModel.inputImageData {
                HStack {
                    ImagePreviewView(imageData: imageData, title: viewModel.inputImageURL?.lastPathComponent ?? "Input")
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        if let url = viewModel.inputImageURL {
                            Label(url.lastPathComponent, systemImage: "photo")
                                .font(.subheadline)
                        }
                        Button("Remove") {
                            viewModel.inputImageData = nil
                            viewModel.inputImageURL = nil
                            viewModel.outputData = nil
                            viewModel.lastResult = nil
                            viewModel.statusMessage = "Ready"
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                    .padding(.trailing)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Drop an image here")
                            .font(.headline)
                        Text("PNG, TIFF, BMP supported")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                    providers.first?.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        DispatchQueue.main.async {
                            viewModel.setInputImage(url: url)
                        }
                    }
                    return true
                }
            }
        }
    }

    // MARK: - Output Panel

    @ViewBuilder
    private var outputPanel: some View {
        GroupBox("Encoding Output") {
            HStack(spacing: 24) {
                metricView(label: "Encoded Size", value: viewModel.encodedSizeString)
                Divider()
                metricView(label: "Compression Ratio", value: viewModel.compressionRatioString)
                Divider()
                metricView(label: "Encoding Time", value: viewModel.encodingTimeString)
            }
            .padding(.vertical, 4)

            if let result = viewModel.lastResult, !result.stageTiming.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stage Timing")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    ForEach(PipelineStage.allCases, id: \.self) { stage in
                        if let duration = result.stageTiming[stage] {
                            HStack {
                                Text(stage.rawValue)
                                    .font(.caption)
                                    .frame(width: 140, alignment: .leading)
                                Spacer()
                                Text(String(format: "%.1f ms", duration * 1000))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Configuration Panel

    @ViewBuilder
    private var configurationPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Preset buttons
                GroupBox("Presets") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(EncodeConfiguration.Preset.allCases, id: \.rawValue) { preset in
                            Button(preset.rawValue) {
                                viewModel.applyPreset(preset)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }

                // Quality
                GroupBox("Quality") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Quality")
                            Spacer()
                            Text(String(format: "%.2f", viewModel.configuration.quality))
                                .monospacedDigit()
                                .frame(width: 40)
                        }
                        Slider(value: $viewModel.configuration.quality, in: 0...1)

                        HStack {
                            Text("Wavelet")
                            Spacer()
                            Picker("Wavelet", selection: $viewModel.configuration.waveletType) {
                                ForEach(WaveletTypeChoice.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                // Tiling
                GroupBox("Tiling") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tile Width")
                            Spacer()
                            TextField("Width", value: $viewModel.configuration.tileWidth, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Tile Height")
                            Spacer()
                            TextField("Height", value: $viewModel.configuration.tileHeight, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                        }
                        Stepper("Decomp Levels: \(viewModel.configuration.decompositionLevels)",
                                value: $viewModel.configuration.decompositionLevels,
                                in: 0...10)
                        Stepper("Quality Layers: \(viewModel.configuration.qualityLayers)",
                                value: $viewModel.configuration.qualityLayers,
                                in: 1...20)
                    }
                }

                // Progression
                GroupBox("Progression") {
                    Picker("Order", selection: $viewModel.configuration.progressionOrder) {
                        ForEach(ProgressionOrderChoice.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                // Feature Flags
                GroupBox("Features") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("MCT (Multi-Component Transform)", isOn: $viewModel.configuration.mctEnabled)
                        Toggle("HTJ2K (Part 15 Fast Encoding)", isOn: $viewModel.configuration.htj2kEnabled)
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
    private func metricView(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func configSummary(_ config: EncodeConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Quality: \(String(format: "%.2f", config.quality))")
                .font(.caption)
            Text("Tile: \(config.tileWidth)×\(config.tileHeight)")
                .font(.caption)
            Text("Wavelet: \(config.waveletType.rawValue)")
                .font(.caption)
            Text("HTJ2K: \(config.htj2kEnabled ? "On" : "Off")")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        return String(format: "%.2f MB", kb / 1024)
    }
}
#endif
