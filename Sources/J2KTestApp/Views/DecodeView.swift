//
// DecodeView.swift
// J2KSwift
//
// Decoding GUI screen with file picker, decode controls, ROI selector,
// resolution level stepper, quality layer slider, component channel
// selector, and codestream marker inspector.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Decode View

/// GUI screen for testing JPEG 2000 decoding.
///
/// Provides a file picker for JP2/J2K/JPX input, a decoded image preview,
/// a region-of-interest selector, resolution level and quality layer
/// controls, a component channel selector, and an expandable marker
/// inspector tree for all codestream markers.
struct DecodeView: View {
    /// View model driving this screen.
    @State var viewModel: DecodeViewModel

    /// Whether the marker inspector panel is expanded.
    @State private var showMarkerInspector: Bool = false

    /// Currently expanded marker node IDs in the inspector tree.
    @State private var expandedMarkers: Set<UUID> = []

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
        .navigationTitle("Decode")
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                // In a real app this would open NSOpenPanel.
                // Simulate loading a file for demonstration.
                let url = URL(fileURLWithPath: "/tmp/sample.jp2")
                viewModel.loadFile(url: url)
            }) {
                Label("Open File…", systemImage: "doc.badge.plus")
            }
            .help("Open a JP2/J2K/JPX file for decoding")

            Spacer()

            Toggle(isOn: $viewModel.isROISelectionActive) {
                Label("ROI", systemImage: "rectangle.dashed")
            }
            .toggleStyle(.button)
            .help("Activate region-of-interest selection tool")

            if viewModel.configuration.regionOfInterest != nil {
                Button(action: { viewModel.clearRegionOfInterest() }) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear region of interest")
            }

            Divider()
                .frame(height: 20)

            Button(action: {
                Task { await viewModel.decode(session: session) }
            }) {
                Label("Decode", systemImage: "arrow.down.doc")
            }
            .disabled(viewModel.isDecoding || viewModel.inputFileURL == nil)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Decode the selected file (⌘↵)")

            Toggle(isOn: $showMarkerInspector) {
                Label("Markers", systemImage: "list.bullet.indent")
            }
            .toggleStyle(.button)
            .help("Show/hide the codestream marker inspector")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                // Codestream header summary
                if !viewModel.codestreamHeaderSummary.isEmpty {
                    headerSummaryBanner
                    Divider()
                }

                // Progress
                if viewModel.isDecoding || viewModel.progress > 0 {
                    ProgressIndicatorView(
                        overallProgress: viewModel.progress,
                        stages: [],
                        statusMessage: viewModel.statusMessage
                    )
                    Divider()
                }

                // Image preview
                if let imageData = viewModel.outputImageData {
                    ImagePreviewView(imageData: imageData, title: "Decoded Image")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No Decoded Image", systemImage: "photo")
                    } description: {
                        Text("Open a JP2/J2K/JPX file and press Decode to see the image.")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // ROI indicator
                if let roi = viewModel.configuration.regionOfInterest {
                    roiIndicator(roi)
                }
            }

            if showMarkerInspector {
                markerInspectorPanel
                    .frame(minWidth: 260, maxWidth: 360)
            }
        }
    }

    // MARK: - Header Summary Banner

    @ViewBuilder
    private var headerSummaryBanner: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(viewModel.codestreamHeaderSummary)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - ROI Indicator

    @ViewBuilder
    private func roiIndicator(_ roi: CGRect) -> some View {
        HStack {
            Image(systemName: "rectangle.dashed")
                .foregroundStyle(.blue)
            Text("ROI: \(Int(roi.width))×\(Int(roi.height)) at (\(Int(roi.minX)), \(Int(roi.minY)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { viewModel.clearRegionOfInterest() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.05))
    }

    // MARK: - Control Panel

    @ViewBuilder
    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Resolution Level
                GroupBox("Resolution Level") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Level")
                            Spacer()
                            Text("\(viewModel.configuration.resolutionLevel)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.configuration.resolutionLevel) },
                                set: { viewModel.configuration.resolutionLevel = Int($0) }
                            ),
                            in: 0...Double(viewModel.maxResolutionLevel),
                            step: 1
                        )
                        Text("0 = full resolution, \(viewModel.maxResolutionLevel) = \(1 << viewModel.maxResolutionLevel)× downscaled")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Quality Layer
                GroupBox("Quality Layer") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Layer")
                            Spacer()
                            Text(viewModel.configuration.qualityLayer == 0 ? "All" : "\(viewModel.configuration.qualityLayer)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.configuration.qualityLayer) },
                                set: { viewModel.configuration.qualityLayer = Int($0) }
                            ),
                            in: 0...Double(viewModel.maxQualityLayer),
                            step: 1
                        )
                        Text("0 = all layers (highest quality)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Component Selector
                GroupBox("Component") {
                    Picker("Channel", selection: Binding(
                        get: { viewModel.configuration.componentIndex ?? -1 },
                        set: { viewModel.configuration.componentIndex = $0 == -1 ? nil : $0 }
                    )) {
                        Text("All Components").tag(-1)
                        Text("Component 0 (Y/R)").tag(0)
                        Text("Component 1 (Cb/G)").tag(1)
                        Text("Component 2 (Cr/B)").tag(2)
                    }
                    .pickerStyle(.radioGroup)
                }

                // Decode Result
                if let result = viewModel.lastResult {
                    GroupBox("Decode Result") {
                        VStack(alignment: .leading, spacing: 4) {
                            metricRow(label: "Dimensions", value: "\(result.imageWidth)×\(result.imageHeight)")
                            metricRow(label: "Components", value: "\(result.componentCount)")
                            metricRow(label: "Decode Time", value: viewModel.decodingTimeString)
                            metricRow(label: "Status", value: result.succeeded ? "✓ Success" : "✗ Failed")
                        }
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

    // MARK: - Marker Inspector Panel

    @ViewBuilder
    private var markerInspectorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Marker Inspector")
                    .font(.headline)
                Spacer()
                Button(action: { showMarkerInspector = false }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if viewModel.markers.isEmpty {
                ContentUnavailableView {
                    Label("No Markers", systemImage: "list.bullet.indent")
                } description: {
                    Text("Open a codestream file to inspect its markers.")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.markers) { marker in
                            markerRow(marker, depth: 0)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    /// Creates a recursive marker tree row.
    private func markerRow(_ marker: CodestreamMarkerInfo, depth: Int) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Indent
                if depth > 0 {
                    Rectangle()
                        .frame(width: CGFloat(depth) * 16, height: 1)
                        .hidden()
                }

                // Expand toggle
                if !marker.children.isEmpty {
                    Button(action: {
                        if expandedMarkers.contains(marker.id) {
                            expandedMarkers.remove(marker.id)
                        } else {
                            expandedMarkers.insert(marker.id)
                        }
                    }) {
                        Image(systemName: expandedMarkers.contains(marker.id) ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 14)
                } else {
                    Spacer().frame(width: 14)
                }

                // Marker name badge
                Text(marker.name)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // Offset
                Text(String(format: "0x%04X", marker.offset))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Summary
                Text(marker.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 3)

            // Children (if expanded)
            if !marker.children.isEmpty && expandedMarkers.contains(marker.id) {
                ForEach(marker.children) { child in
                    markerRow(child, depth: depth + 1)
                        .padding(.leading, 16)
                }
            }
        })
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metricRow(label: String, value: String) -> some View {
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
