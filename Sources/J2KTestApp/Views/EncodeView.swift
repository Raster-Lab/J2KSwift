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
import AppKit
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

            ZStack {
                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    tabContent
                }

                // Encoding overlay
                if viewModel.isEncoding {
                    encodingOverlay
                }
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

            Button(action: browseForInputImage) {
                Label("Browse…", systemImage: "folder")
            }
            .disabled(viewModel.isEncoding)
            .help("Select an input image file")
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

    // MARK: - Encoding Overlay

    @ViewBuilder
    private var encodingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.5)

                Text(viewModel.statusMessage.isEmpty ? "Encoding…" : viewModel.statusMessage)
                    .font(.headline)
                    .foregroundStyle(.white)

                if viewModel.progress > 0 && viewModel.progress < 1 {
                    ProgressView(value: viewModel.progress)
                        .frame(width: 200)
                        .tint(.white)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isEncoding)
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

            if let originalData = viewModel.inputImageData, viewModel.decodedOutputImageData != nil {
                Divider()
                ImageComparisonView(
                    originalData: originalData,
                    processedData: viewModel.decodedOutputImageData
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
                Button(action: browseForBatchFolder) {
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
                        Text("PNG, TIFF, BMP, DICOM supported")
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
                        if let duration = result.stageTiming[stage], duration > 0 {
                            HStack {
                                Text(stage.rawValue)
                                    .font(.caption)
                                    .frame(width: 140, alignment: .leading)
                                Spacer()
                                Text(EncodeViewModel.formatDuration(duration))
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
                            let isSelected = viewModel.selectedPreset == preset
                            Button(action: {
                                viewModel.applyPreset(preset)
                            }) {
                                Text(preset.rawValue)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected ? .accentColor : nil)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                            )
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

                // Action Buttons
                VStack(spacing: 8) {
                    Button(action: {
                        Task { await viewModel.encode(session: session) }
                    }) {
                        Label("Encode", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isEncoding || viewModel.inputImageData == nil)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("Encode the selected image (⌘↵)")

                    Button(action: saveEncodedOutput) {
                        Label("Save…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.outputData == nil)
                    .help("Save encoded output to file")
                }
                .padding(.top, 8)
            }
            .padding()
            .onChange(of: viewModel.configuration) { _, _ in
                if !viewModel.isApplyingPreset {
                    viewModel.selectedPreset = nil
                }
            }
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

    // MARK: - File Dialogs

    /// Opens an NSOpenPanel to select an input image for encoding.
    private func browseForInputImage() {
        let panel = NSOpenPanel()
        panel.title = "Select Image"
        panel.allowedContentTypes = [
            .png, .tiff, .bmp, .data,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.setInputImage(url: url)
    }

    /// Opens an NSSavePanel to save the encoded JPEG 2000 output.
    private func saveEncodedOutput() {
        guard let data = viewModel.outputData else { return }
        let panel = NSSavePanel()
        panel.title = "Save Encoded Output"
        panel.nameFieldStringValue = suggestedOutputFilename()
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            viewModel.statusMessage = "Saved to \(url.lastPathComponent)"
        } catch {
            viewModel.statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Opens an NSOpenPanel to select a folder for batch encoding.
    private func browseForBatchFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Image Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imageExtensions: Set<String> = ["png", "tiff", "tif", "bmp", "dcm", "dicom"]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ).filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []
        viewModel.setBatchInputURLs(urls)
    }

    /// Suggests an output filename based on the input name and configuration.
    private func suggestedOutputFilename() -> String {
        let base = viewModel.inputImageURL?.deletingPathExtension().lastPathComponent ?? "encoded"
        let ext = viewModel.configuration.htj2kEnabled ? "jph" : "j2k"
        return "\(base).\(ext)"
    }
}
#endif
