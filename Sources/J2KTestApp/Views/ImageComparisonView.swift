//
// ImageComparisonView.swift
// J2KSwift
//
// Image comparison view with side-by-side, overlay, and difference modes.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Comparison Mode

/// Display mode for image comparison.
enum ComparisonMode: String, CaseIterable {
    /// Side-by-side display.
    case sideBySide = "Side by Side"
    /// Overlay with opacity slider.
    case overlay = "Overlay"
    /// Pixel difference visualisation.
    case difference = "Difference"
}

// MARK: - Image Comparison View

/// Image comparison view supporting side-by-side, overlay, and difference modes.
///
/// Displays two images with multiple comparison modes for visual inspection
/// of encoding/decoding quality. Includes controls for switching modes and
/// adjusting overlay opacity.
struct ImageComparisonView: View {
    /// Data for the first (original) image.
    let originalData: Data?
    /// Data for the second (processed) image.
    let processedData: Data?

    /// Current comparison mode.
    @State private var comparisonMode: ComparisonMode = .sideBySide
    /// Overlay opacity for overlay mode.
    @State private var overlayOpacity: Double = 0.5

    var body: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $comparisonMode) {
                ForEach(ComparisonMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            switch comparisonMode {
            case .sideBySide:
                HStack(spacing: 4) {
                    ImagePreviewView(imageData: originalData, title: "Original")
                    Divider()
                    ImagePreviewView(imageData: processedData, title: "Processed")
                }
            case .overlay:
                ZStack {
                    ImagePreviewView(imageData: originalData, title: "Original")
                    ImagePreviewView(imageData: processedData, title: "Processed")
                        .opacity(overlayOpacity)
                }
                Slider(value: $overlayOpacity, in: 0...1) {
                    Text("Opacity")
                }
                .frame(maxWidth: 200)
            case .difference:
                VStack {
                    ImagePreviewView(imageData: processedData, title: "Difference")
                    Text("Difference mode highlights pixel-level discrepancies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
#endif
