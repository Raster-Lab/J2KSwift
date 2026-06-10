//
// ImageComparisonView.swift
// J2KSwift
//
// Image comparison view with side-by-side, overlay, and difference modes.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AppKit
import J2KCore
import J2KTestAppCore

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
                    if let diffImage = computeDifferenceImage() {
                        Image(nsImage: diffImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ImagePreviewView(imageData: processedData, title: "Difference")
                    }
                    Text("Amplified pixel difference (10× gain, red channel).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    /// Computes a difference image between original and processed data.
    ///
    /// Returns an NSImage showing amplified absolute per-pixel differences
    /// mapped to a heat-map (black = identical, red/yellow = large difference).
    private func computeDifferenceImage() -> NSImage? {
        guard let origData = originalData,
              let procData = processedData,
              let origImage = NSImage(data: origData),
              let procImage = NSImage(data: procData) else { return nil }

        guard let origCG = origImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let procCG = procImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let w = min(origCG.width, procCG.width)
        let h = min(origCG.height, procCG.height)
        guard w > 0, h > 0 else { return nil }

        let bytesPerRow = w * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let origCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                       bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo),
              let procCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        origCtx.draw(origCG, in: rect)
        procCtx.draw(procCG, in: rect)

        guard let origPixels = origCtx.data?.assumingMemoryBound(to: UInt8.self),
              let procPixels = procCtx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        guard let diffCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                       bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
        guard let diffPixels = diffCtx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        let gain = 10  // amplification factor
        let totalPixels = w * h

        for i in 0..<totalPixels {
            let off = i * 4
            let dr = abs(Int(origPixels[off]) - Int(procPixels[off]))
            let dg = abs(Int(origPixels[off + 1]) - Int(procPixels[off + 1]))
            let db = abs(Int(origPixels[off + 2]) - Int(procPixels[off + 2]))
            let maxDiff = max(dr, max(dg, db))
            let amplified = min(255, maxDiff * gain)
            // Heat map: low diffs → dark red, high diffs → yellow/white
            diffPixels[off]     = UInt8(min(255, amplified))           // R
            diffPixels[off + 1] = UInt8(min(255, amplified / 2))      // G
            diffPixels[off + 2] = 0                                     // B
            diffPixels[off + 3] = 255                                   // A
        }

        guard let diffCG = diffCtx.makeImage() else { return nil }
        return NSImage(cgImage: diffCG, size: NSSize(width: w, height: h))
    }
}
#endif
