//
// ValidationView.swift
// J2KSwift
//
// Codestream and file format validation tools screen.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// GUI screen for codestream and file format validation.
///
/// Provides three modes: codestream syntax validation with drag-and-drop
/// and pass/fail with error list, JP2/JPX/JPM file format structure tree
/// with validity indicators, and marker segment inspector with hex dump
/// and highlighted boundaries.
struct ValidationView: View {
    @State var viewModel: ValidationViewModel

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
        .navigationTitle("Validation")
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack {
            Button(action: {
                Task { await viewModel.validate(session: session) }
            }) {
                Label("Validate", systemImage: "checkmark.shield")
            }
            .disabled(viewModel.isValidating || viewModel.inputFileURL == nil)

            Picker("Mode", selection: $viewModel.selectedMode) {
                ForEach(ValidationMode.allCases, id: \.rawValue) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            if viewModel.isValidating {
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
        VStack(alignment: .leading, spacing: 16) {
            // File drop area
            Text("Input File")
                .font(.headline)

            if let url = viewModel.inputFileURL {
                Label(url.lastPathComponent, systemImage: "doc.fill")
                    .font(.caption)

                if let passed = viewModel.validationPassed {
                    HStack {
                        Image(systemName: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(passed ? .green : .red)
                        Text(passed ? "Valid" : "Invalid")
                            .font(.caption.bold())
                            .foregroundStyle(passed ? .green : .red)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Drop a J2K/JP2/JPX file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Mode description
            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    /// Description of the currently selected validation mode.
    private var modeDescription: String {
        switch viewModel.selectedMode {
        case .codestream:
            return "Validates J2K/J2C codestream syntax. Checks marker segment order, parameter validity, and structural integrity."
        case .fileFormat:
            return "Validates JP2/JPX/JPM box structure. Inspects box hierarchy, required boxes, and field validity."
        case .markerInspector:
            return "Inspects all marker segments with hex dump display. Shows decoded field values and byte boundaries."
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.selectedMode {
        case .codestream:
            codestreamValidationContent
        case .fileFormat:
            fileFormatContent
        case .markerInspector:
            markerInspectorContent
        }
    }

    // MARK: - Codestream Validation

    @ViewBuilder
    private var codestreamValidationContent: some View {
        if viewModel.findings.isEmpty {
            ContentUnavailableView {
                Label("No Findings", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Load a codestream file and run validation to see findings.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.findings) { finding in
                        findingRow(finding: finding)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func findingRow(finding: ValidationFinding) -> some View {
        HStack(spacing: 8) {
            Image(systemName: findingIcon(for: finding.severity))
                .foregroundStyle(findingColour(for: finding.severity))
                .frame(width: 16)

            Text(String(format: "0x%04X", finding.offset))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(finding.message)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func findingIcon(for severity: ValidationSeverity) -> String {
        switch severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func findingColour(for severity: ValidationSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    // MARK: - File Format Tree

    @ViewBuilder
    private var fileFormatContent: some View {
        if viewModel.boxTree.isEmpty {
            ContentUnavailableView {
                Label("No Box Structure", systemImage: "rectangle.3.group")
            } description: {
                Text("Load a JP2/JPX/JPM file and validate to see the box structure.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.boxTree) { box in
                        boxRow(box: box, indent: 0)
                    }
                }
                .padding()
            }
        }
    }


    private func boxRow(box: FileFormatBoxInfo, indent: Int) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: box.isValid ? "checkmark.square.fill" : "xmark.square.fill")
                    .foregroundStyle(box.isValid ? .green : .red)
                    .font(.caption)

                Text(box.boxType)
                    .font(.caption.monospaced().bold())

                Text(box.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(box.length) bytes")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, CGFloat(indent * 20))
            .padding(.vertical, 2)

            ForEach(box.children) { child in
                boxRow(box: child, indent: indent + 1)
            }
        })
    }

    // MARK: - Marker Inspector

    @ViewBuilder
    private var markerInspectorContent: some View {
        if viewModel.markerSegments.isEmpty {
            ContentUnavailableView {
                Label("No Markers", systemImage: "text.magnifyingglass")
            } description: {
                Text("Load a codestream file and inspect markers to see the hex dump.")
            }
        } else {
            VSplitView {
                // Marker list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.markerSegments) { marker in
                            markerRow(marker: marker, indent: 0)
                        }
                    }
                    .padding()
                }
                .frame(minHeight: 150)

                // Hex dump panel
                VStack(alignment: .leading) {
                    Text("Hex Dump")
                        .font(.caption.bold())
                    Text(viewModel.selectedMarkerHex.isEmpty
                         ? "Select a marker to view hex data."
                         : viewModel.selectedMarkerHex)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
                .padding()
                .frame(minHeight: 80)
            }
        }
    }

    @ViewBuilder
    private func markerRow(marker: CodestreamMarkerInfo, indent: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.tint)
                    .font(.caption)

                Text(marker.name)
                    .font(.caption.monospaced().bold())

                Text(String(format: "@ 0x%04X", marker.offset))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let length = marker.length {
                    Text("(\(length) bytes)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(marker.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, CGFloat(indent * 16))
            .padding(.vertical, 2)

            ForEach(marker.children) { child in
                markerRow(marker: child, indent: indent + 1)
            }
        }
    }
}
#endif
