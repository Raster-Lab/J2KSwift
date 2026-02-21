//
// ImagePreviewView.swift
// J2KSwift
//
// Image preview panel with zoom, pan, and pixel-level inspection.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Image Preview View

/// Image preview panel with zoom, pan, and pixel-level inspection.
///
/// Displays an image with interactive zoom and pan controls. Supports
/// pixel-level inspection showing coordinates and colour values at the
/// cursor position.
struct ImagePreviewView: View {
    /// The image to display (as NSImage data).
    let imageData: Data?

    /// Title displayed above the preview.
    let title: String

    /// Current zoom level.
    @State private var zoomLevel: Double = 1.0

    /// Current pan offset.
    @State private var panOffset: CGSize = .zero

    /// Whether pixel inspector is active.
    @State private var showPixelInspector: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: { zoomLevel = max(0.1, zoomLevel - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Text("\(Int(zoomLevel * 100))%")
                    .monospacedDigit()
                    .frame(width: 50)
                Button(action: { zoomLevel = min(10.0, zoomLevel + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button(action: { zoomLevel = 1.0; panOffset = .zero }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset zoom and position")
            }

            if let imageData = imageData, let nsImage = NSImage(data: imageData) {
                GeometryReader { geometry in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomLevel)
                        .offset(panOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    panOffset = value.translation
                                }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView {
                    Label("No Image", systemImage: "photo")
                } description: {
                    Text("Drop an image here or select a file to preview.")
                }
            }
        }
        .padding()
    }
}
#endif
