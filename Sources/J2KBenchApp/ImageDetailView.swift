//
// ImageDetailView.swift
// J2KBenchApp — image viewer
//
// Displays a decoded image: a pinch-zoom / pan canvas on top, an
// inspector panel below (dimensions, bit depth, components, sizes),
// the decode time with a re-time control, and — for a photo
// round-trip — the compression ratio and PSNR.

import SwiftUI
import UIKit
import J2KCodec

struct ImageDetailView: View {
    let image: ViewerImage

    @State private var decodeMS: Double
    @State private var retiming = false

    init(image: ViewerImage) {
        self.image = image
        _decodeMS = State(initialValue: image.decodeMS)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZoomableImageView(image: image.uiImage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            Divider()
            inspector
                .frame(height: 252)
        }
        .navigationTitle(image.sourceLabel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(spacing: 0) {
                row("Dimensions",
                    "\(image.width) \u{00d7} \(image.height)  \u{00b7}  \(megapixels) MP")
                row("Components", componentsText)
                row("Bit depth",
                    "\(image.bitDepth)-bit\(image.signed ? " signed" : "")")
                row("Colour space", image.colorSpace)
                if let fileBytes = image.fileBytes {
                    row("File size", byteText(fileBytes))
                }
                row("Codestream", byteText(image.codestreamBytes))
                timingRow
                if let rt = image.roundTrip {
                    row("Compression",
                        String(format: "%.2f\u{00d7}", rt.compressionRatio))
                    row("PSNR", rt.psnr.map { String(format: "%.1f dB", $0) }
                        ?? "Exact \u{2014} lossless")
                }
            }
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    private var megapixels: String {
        String(format: "%.1f", Double(image.width * image.height) / 1_000_000)
    }

    private var componentsText: String {
        switch image.componentCount {
        case 1:  return "1 (grayscale)"
        case 3:  return "3 (colour)"
        case 4:  return "4 (colour + alpha)"
        default: return "\(image.componentCount)"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 7)
    }

    private var timingRow: some View {
        HStack {
            Text("Decode time").foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f ms", decodeMS))
                .font(.subheadline.monospacedDigit().weight(.medium))
            Button(action: retime) {
                if retiming {
                    ProgressView()
                } else {
                    Label("Re-time", systemImage: "stopwatch")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .disabled(retiming)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 7)
    }

    // MARK: - Re-time

    private func retime() {
        retiming = true
        Task {
            let decoder = J2KDecoder()
            var samples: [Double] = []
            do {
                for _ in 0..<2 { _ = try await decoder.decode(image.codestream) }
                for _ in 0..<5 {
                    let t0 = DispatchTime.now().uptimeNanoseconds
                    _ = try await decoder.decode(image.codestream)
                    let t1 = DispatchTime.now().uptimeNanoseconds
                    samples.append(Double(t1 - t0) / 1_000_000)
                }
                samples.sort()
                decodeMS = samples[samples.count / 2]
            } catch {
                // Leave the original timing if a re-decode fails.
            }
            retiming = false
        }
    }
}

// MARK: - Zoomable image canvas

/// `UIScrollView`-backed pinch-zoom / pan canvas. Double-tap toggles
/// between fit and 3×. Resets only when the image itself changes, so
/// re-timing (which re-renders the parent) doesn't drop the zoom.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.delegate = context.coordinator
        scroll.maximumZoomScale = 8
        scroll.minimumZoomScale = 1
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.imageView.image = image
        context.coordinator.imageView = scroll.imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: ZoomScrollView, context: Context) {
        if scroll.imageView.image !== image {
            scroll.imageView.image = image
            scroll.zoomScale = 1
            scroll.setNeedsLayout()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                scroll.setZoomScale(min(3, scroll.maximumZoomScale), animated: true)
            }
        }
    }
}

/// Scroll view that keeps its image view fitted to the bounds while
/// unzoomed (so rotation / first layout always letterboxes correctly).
final class ZoomScrollView: UIScrollView {
    let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(imageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == minimumZoomScale {
            imageView.frame = bounds
        }
    }
}
