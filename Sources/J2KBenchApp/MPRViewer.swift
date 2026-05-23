//
// MPRViewer.swift
// J2KBenchApp — v10.18-research JP3D arc
//
// 3-plane multi-planar reconstruction viewer (axial + sagittal +
// coronal) with crosshair sync. The demo-grade verification surface
// for the JP3D partial-resolution / ROI ports: switching the decode-
// mode picker re-decodes the fixture and re-renders all three planes,
// so an A/B for full vs `resolutionLevel:1` vs `decodeRegion(.quarter)`
// is a one-tap operation, with the decode wall-time printed next to
// the toggle.
//
// Architecture:
//
//   • `MPRViewerView`        — root: owns `MPRViewerModel`, renders
//                              the picker / three planes / sliders.
//   • `MPRViewerModel`       — loads the codestream lazily (synth →
//                              encode once per fixture, kept in-memory),
//                              decodes for the current mode, exposes
//                              `volume`, `decodeMS`, and crosshair
//                              indices.
//   • `MPRSliceExtractor`    — pure function: J2KVolume + axis + index
//                              → 8-bit grayscale `CGImage`. Window-
//                              stretches multi-byte samples to the
//                              volume's actual min/max range.
//   • `MPRPlaneView`         — one plane: the slice image + crosshair
//                              overlay + tap-to-set-crosshair gesture
//                              + Z/X/Y slider.

import SwiftUI
import J2KCore
import J2K3D

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Route + root view

struct MPRViewerView: View {
    let fixture: JP3DFixture
    @StateObject private var model: MPRViewerModel

    init(fixture: JP3DFixture) {
        self.fixture = fixture
        _model = StateObject(wrappedValue: MPRViewerModel(fixture: fixture))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            body_content
        }
        .navigationTitle(fixture.label)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.prepareAndDecode() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Decode mode", selection: $model.mode) {
                ForEach(MPRViewerModel.Mode.allCases, id: \.self) { m in
                    Text(m.shortLabel).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.mode) { _, _ in
                Task { await model.decodeForCurrentMode() }
            }

            HStack {
                if model.isDecoding {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Decoding\u{2026}").font(.caption)
                    }
                } else if let ms = model.decodeMS {
                    Text("\(model.mode.shortLabel) decode: \(String(format: "%.1f", ms)) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let v = model.volume {
                    Text("\(v.width)\u{00d7}\(v.height)\u{00d7}\(v.depth)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var body_content: some View {
        if let err = model.error {
            errorState(err)
        } else if model.volume == nil {
            ProgressView("Synthesising + encoding\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            planes
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Decode failed").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Stacked layout works well on all iPhone sizes; iPad gets the
    /// same vertical stack — three big planes a finger can interact
    /// with beats a 2x2 grid where the cells are too small.
    private var planes: some View {
        ScrollView {
            VStack(spacing: 12) {
                MPRPlaneView(plane: .axial,    model: model)
                MPRPlaneView(plane: .sagittal, model: model)
                MPRPlaneView(plane: .coronal,  model: model)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

// MARK: - Model

@MainActor
final class MPRViewerModel: ObservableObject {

    enum Mode: CaseIterable, Hashable {
        case full
        case res1
        case roiQuarter

        var shortLabel: String {
            switch self {
            case .full:       return "Full"
            case .res1:       return "Res-1"
            case .roiQuarter: return "ROI 1/4"
            }
        }
    }

    @Published var mode: Mode = .full
    @Published private(set) var volume: J2KVolume?
    @Published private(set) var decodeMS: Double?
    @Published private(set) var isDecoding: Bool = false
    @Published private(set) var error: String?

    // Crosshair indices into the *currently decoded* volume.
    @Published var crossX: Int = 0
    @Published var crossY: Int = 0
    @Published var crossZ: Int = 0

    /// Per-volume window-stretch range, computed on decode so the
    /// slice extractor doesn't re-scan every render.
    @Published private(set) var sampleMin: Int = 0
    @Published private(set) var sampleMax: Int = 0

    private let fixture: JP3DFixture
    private var codestream: Data?
    private var encodeMS: Double?

    init(fixture: JP3DFixture) { self.fixture = fixture }

    /// One-time per push: synthesise + encode the fixture, then run
    /// the initial decode for the current `mode`. Subsequent mode
    /// changes only re-decode, never re-encode.
    func prepareAndDecode() async {
        guard codestream == nil else { return }
        do {
            let volume = JP3DSampleSource.synthesize(fixture)
            let encoder = JP3DSampleSource.losslessHTEncoder()
            let t0 = DispatchTime.now().uptimeNanoseconds
            let enc = try await encoder.encode(volume)
            let t1 = DispatchTime.now().uptimeNanoseconds
            encodeMS = Double(t1 - t0) / 1_000_000.0
            codestream = enc.data
            await decodeForCurrentMode()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Re-decode `codestream` for the current `mode`. Called by the
    /// initial load AND every time `mode` changes.
    func decodeForCurrentMode() async {
        guard let data = codestream else { return }
        isDecoding = true
        error = nil
        defer { isDecoding = false }

        do {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let v: J2KVolume
            switch mode {
            case .full:
                v = try await JP3DDecoder().decode(data).volume
            case .res1:
                let cfg = JP3DDecoderConfiguration(resolutionLevel: 1)
                v = try await JP3DDecoder(configuration: cfg).decode(data).volume
            case .roiQuarter:
                let roi = fixture.centreQuarterROI
                let region = JP3DRegion(x: roi.x, y: roi.y, z: roi.z)
                v = try await JP3DROIDecoder().decode(data, region: region).volume
            }
            let t1 = DispatchTime.now().uptimeNanoseconds
            decodeMS = Double(t1 - t0) / 1_000_000.0
            volume = v
            updateSampleRange(for: v)
            recentreCrosshair(for: v)
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Internal helpers

    /// Single pass to derive window-stretch bounds. Synthetic LCG
    /// noise spans the full bit-depth range so a fixed-range guess
    /// would also work, but a real-DICOM extension will need the
    /// data-driven version.
    private func updateSampleRange(for v: J2KVolume) {
        guard let comp = v.components.first else {
            sampleMin = 0; sampleMax = 0; return
        }
        var minS = Int.max
        var maxS = Int.min
        comp.data.withUnsafeBytes { raw in
            switch comp.bytesPerSample {
            case 1:
                let p = raw.bindMemory(to: UInt8.self)
                for i in 0..<p.count {
                    let s = Int(p[i])
                    if s < minS { minS = s }
                    if s > maxS { maxS = s }
                }
            case 2:
                let p = raw.bindMemory(to: UInt16.self)
                for i in 0..<p.count {
                    let s = Int(p[i])
                    if s < minS { minS = s }
                    if s > maxS { maxS = s }
                }
            default:
                minS = 0
                maxS = (1 << comp.bitDepth) - 1
            }
        }
        if minS >= maxS { maxS = minS + 1 }
        sampleMin = minS
        sampleMax = maxS
    }

    private func recentreCrosshair(for v: J2KVolume) {
        crossX = min(max(crossX, 0), max(0, v.width - 1))
        crossY = min(max(crossY, 0), max(0, v.height - 1))
        crossZ = min(max(crossZ, 0), max(0, v.depth - 1))
        // Initial centring on first decode.
        if crossX == 0 && crossY == 0 && crossZ == 0 {
            crossX = v.width / 2
            crossY = v.height / 2
            crossZ = v.depth / 2
        }
    }
}

// MARK: - Plane view

enum MPRPlane {
    case axial    // XY at Z
    case sagittal // YZ at X
    case coronal  // XZ at Y

    var label: String {
        switch self {
        case .axial:    return "Axial"
        case .sagittal: return "Sagittal"
        case .coronal:  return "Coronal"
        }
    }
}

#if canImport(UIKit)

struct MPRPlaneView: View {
    let plane: MPRPlane
    @ObservedObject var model: MPRViewerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plane.label).font(.subheadline.weight(.semibold))
                Spacer()
                indexLabel
            }
            sliceCanvas
            slider
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Index + slider

    private var indexLabel: some View {
        Group {
            switch plane {
            case .axial:    Text("Z = \(model.crossZ)").font(.caption.monospacedDigit())
            case .sagittal: Text("X = \(model.crossX)").font(.caption.monospacedDigit())
            case .coronal:  Text("Y = \(model.crossY)").font(.caption.monospacedDigit())
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var slider: some View {
        if let v = model.volume {
            switch plane {
            case .axial:
                let upper = max(0, v.depth - 1)
                Slider(value: zBinding(upper: upper),
                       in: 0...Double(upper),
                       step: 1)
            case .sagittal:
                let upper = max(0, v.width - 1)
                Slider(value: xBinding(upper: upper),
                       in: 0...Double(upper),
                       step: 1)
            case .coronal:
                let upper = max(0, v.height - 1)
                Slider(value: yBinding(upper: upper),
                       in: 0...Double(upper),
                       step: 1)
            }
        }
    }

    private func zBinding(upper: Int) -> Binding<Double> {
        Binding(get: { Double(min(model.crossZ, upper)) },
                set: { model.crossZ = Int($0) })
    }
    private func xBinding(upper: Int) -> Binding<Double> {
        Binding(get: { Double(min(model.crossX, upper)) },
                set: { model.crossX = Int($0) })
    }
    private func yBinding(upper: Int) -> Binding<Double> {
        Binding(get: { Double(min(model.crossY, upper)) },
                set: { model.crossY = Int($0) })
    }

    // MARK: - Slice canvas

    private var sliceCanvas: some View {
        GeometryReader { geo in
            let img = currentImage()
            ZStack {
                if let cg = img {
                    Image(decorative: cg, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                }
                CrosshairOverlay(plane: plane, model: model, canvas: geo.size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in handleTap(at: value.location, in: geo.size) }
            )
        }
        .aspectRatio(planeAspect(), contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Tap-to-crosshair: maps the (x, y) point in canvas coordinates
    /// to voxel-space along the two in-plane axes, then nudges the
    /// other plane's crosshair to match. Crosshair sync falls out
    /// naturally: each plane updates two of the three indices, the
    /// other planes re-render with their slider tracking the new
    /// third index.
    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard let v = model.volume else { return }
        let aspect = planeAspect()
        let imgFrame = aspectFitRect(in: size, aspect: aspect)
        let local = CGPoint(x: point.x - imgFrame.minX, y: point.y - imgFrame.minY)
        guard imgFrame.width > 0, imgFrame.height > 0,
              local.x >= 0, local.x <= imgFrame.width,
              local.y >= 0, local.y <= imgFrame.height else { return }
        let nx = max(0, min(1, local.x / imgFrame.width))
        let ny = max(0, min(1, local.y / imgFrame.height))

        switch plane {
        case .axial: // XY plane: x→X, y→Y; leaves Z
            model.crossX = clamp(Int(nx * Double(v.width)),  0, v.width - 1)
            model.crossY = clamp(Int(ny * Double(v.height)), 0, v.height - 1)
        case .sagittal: // YZ plane: x→Y (across), y→Z (down)
            model.crossY = clamp(Int(nx * Double(v.height)), 0, v.height - 1)
            model.crossZ = clamp(Int(ny * Double(v.depth)),  0, v.depth - 1)
        case .coronal: // XZ plane: x→X, y→Z
            model.crossX = clamp(Int(nx * Double(v.width)),  0, v.width - 1)
            model.crossZ = clamp(Int(ny * Double(v.depth)),  0, v.depth - 1)
        }
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), max(lo, hi))
    }

    /// Aspect ratio of this plane's slice, in pixels. Honours the
    /// volume's `spacingX/Y/Z` (1:1:1 for synthetic; non-isotropic
    /// for real DICOM later).
    private func planeAspect() -> CGFloat {
        guard let v = model.volume else { return 1 }
        let sx = max(v.spacingX, 0.001)
        let sy = max(v.spacingY, 0.001)
        let sz = max(v.spacingZ, 0.001)
        switch plane {
        case .axial:    return CGFloat((Double(v.width) * sx) / (Double(v.height) * sy))
        case .sagittal: return CGFloat((Double(v.height) * sy) / (Double(v.depth) * sz))
        case .coronal:  return CGFloat((Double(v.width) * sx) / (Double(v.depth) * sz))
        }
    }

    private func aspectFitRect(in container: CGSize, aspect: CGFloat) -> CGRect {
        guard aspect > 0, container.width > 0, container.height > 0 else { return .zero }
        let containerAspect = container.width / container.height
        let w: CGFloat
        let h: CGFloat
        if aspect >= containerAspect {
            w = container.width
            h = container.width / aspect
        } else {
            h = container.height
            w = container.height * aspect
        }
        let x = (container.width - w) / 2
        let y = (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func currentImage() -> CGImage? {
        guard let v = model.volume else { return nil }
        switch plane {
        case .axial:
            return MPRSliceExtractor.slice(
                volume: v, plane: .axial, index: model.crossZ,
                minSample: model.sampleMin, maxSample: model.sampleMax)
        case .sagittal:
            return MPRSliceExtractor.slice(
                volume: v, plane: .sagittal, index: model.crossX,
                minSample: model.sampleMin, maxSample: model.sampleMax)
        case .coronal:
            return MPRSliceExtractor.slice(
                volume: v, plane: .coronal, index: model.crossY,
                minSample: model.sampleMin, maxSample: model.sampleMax)
        }
    }
}

// MARK: - Crosshair overlay

struct CrosshairOverlay: View {
    let plane: MPRPlane
    @ObservedObject var model: MPRViewerModel
    let canvas: CGSize

    var body: some View {
        Canvas { ctx, _ in
            guard let v = model.volume else { return }
            let aspect = planeAspect(v: v)
            let imgFrame = aspectFitRect(in: canvas, aspect: aspect)
            let (uFraction, vFraction) = inPlaneFractions(v: v)

            let x = imgFrame.minX + imgFrame.width * uFraction
            let y = imgFrame.minY + imgFrame.height * vFraction

            var v0 = Path()
            v0.move(to: CGPoint(x: x, y: imgFrame.minY))
            v0.addLine(to: CGPoint(x: x, y: imgFrame.maxY))
            ctx.stroke(v0, with: .color(.yellow.opacity(0.8)), lineWidth: 1)

            var h0 = Path()
            h0.move(to: CGPoint(x: imgFrame.minX, y: y))
            h0.addLine(to: CGPoint(x: imgFrame.maxX, y: y))
            ctx.stroke(h0, with: .color(.yellow.opacity(0.8)), lineWidth: 1)
        }
    }

    private func inPlaneFractions(v: J2KVolume) -> (Double, Double) {
        switch plane {
        case .axial:
            return (Double(model.crossX) / Double(max(v.width, 1)),
                    Double(model.crossY) / Double(max(v.height, 1)))
        case .sagittal:
            return (Double(model.crossY) / Double(max(v.height, 1)),
                    Double(model.crossZ) / Double(max(v.depth, 1)))
        case .coronal:
            return (Double(model.crossX) / Double(max(v.width, 1)),
                    Double(model.crossZ) / Double(max(v.depth, 1)))
        }
    }

    private func planeAspect(v: J2KVolume) -> CGFloat {
        let sx = max(v.spacingX, 0.001)
        let sy = max(v.spacingY, 0.001)
        let sz = max(v.spacingZ, 0.001)
        switch plane {
        case .axial:    return CGFloat((Double(v.width) * sx) / (Double(v.height) * sy))
        case .sagittal: return CGFloat((Double(v.height) * sy) / (Double(v.depth) * sz))
        case .coronal:  return CGFloat((Double(v.width) * sx) / (Double(v.depth) * sz))
        }
    }

    private func aspectFitRect(in container: CGSize, aspect: CGFloat) -> CGRect {
        guard aspect > 0, container.width > 0, container.height > 0 else { return .zero }
        let containerAspect = container.width / container.height
        let w: CGFloat
        let h: CGFloat
        if aspect >= containerAspect {
            w = container.width
            h = container.width / aspect
        } else {
            h = container.height
            w = container.height * aspect
        }
        let x = (container.width - w) / 2
        let y = (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

#endif  // canImport(UIKit)

// MARK: - Slice extractor

/// Pure function: pull a slice from a J2KVolume's first component and
/// produce an 8-bit grayscale `CGImage`. Window-stretches multi-byte
/// samples to `[minSample, maxSample]` so 16-bit volumes are visible
/// without per-pixel scanning each render.
enum MPRSliceExtractor {

    static func slice(
        volume: J2KVolume,
        plane: MPRPlane,
        index: Int,
        minSample: Int,
        maxSample: Int
    ) -> CGImage? {
        guard let comp = volume.components.first else { return nil }
        let bps = comp.bytesPerSample
        let W = volume.width
        let H = volume.height
        let D = volume.depth
        let denom = max(1, maxSample - minSample)

        let (outW, outH): (Int, Int)
        switch plane {
        case .axial:    (outW, outH) = (W, H)
        case .sagittal: (outW, outH) = (H, D)
        case .coronal:  (outW, outH) = (W, D)
        }
        guard outW > 0, outH > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: outW * outH)

        comp.data.withUnsafeBytes { raw in
            // Closure: read one voxel as a normalised UInt8.
            let readByte: (Int, Int, Int) -> UInt8 = { x, y, z in
                let i = (z * W * H) + (y * W) + x
                let s: Int
                if bps == 1 {
                    s = Int(raw.bindMemory(to: UInt8.self)[i])
                } else if bps == 2 {
                    s = Int(raw.bindMemory(to: UInt16.self)[i])
                } else {
                    s = 0
                }
                let clamped = min(max(s - minSample, 0), denom)
                return UInt8(clamped * 255 / denom)
            }

            switch plane {
            case .axial:
                let z = min(max(index, 0), D - 1)
                for y in 0..<H {
                    for x in 0..<W {
                        pixels[y * W + x] = readByte(x, y, z)
                    }
                }
            case .sagittal:
                // Output rows = z (top→bottom = z 0→D-1), cols = y
                let x = min(max(index, 0), W - 1)
                for z in 0..<D {
                    for y in 0..<H {
                        pixels[z * H + y] = readByte(x, y, z)
                    }
                }
            case .coronal:
                // Output rows = z, cols = x
                let y = min(max(index, 0), H - 1)
                for z in 0..<D {
                    for x in 0..<W {
                        pixels[z * W + x] = readByte(x, y, z)
                    }
                }
            }
        }

        return makeGrayCGImage(pixels: pixels, width: outW, height: outH)
    }

    private static func makeGrayCGImage(
        pixels: [UInt8], width: Int, height: Int
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width
        guard let provider = CGDataProvider(data: Data(pixels) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)
    }
}
