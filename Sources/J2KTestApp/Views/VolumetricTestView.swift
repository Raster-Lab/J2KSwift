//
// VolumetricTestView.swift
// J2KSwift
//
// JP3D volumetric testing dashboard: volume loader, slice navigator,
// 3D wavelet parameters, per-slice quality metrics, and comparison view.
//

#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI
import J2KCore
import J2K3D

/// GUI screen for JP3D volumetric testing.
///
/// Provides volume loader controls, a slice navigator with axial/coronal/sagittal
/// plane selection, 3D wavelet parameter panel, per-slice quality metrics table,
/// and a comparison view showing real original vs decoded slices with difference overlay.
struct VolumetricTestView: View {
    @State var viewModel: VolumetricTestViewModel
    @State private var hasAutoLoadedDefaultSource = false

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
        .navigationTitle("JP3D Volumetric Testing")
        .task {
            if !hasAutoLoadedDefaultSource {
                hasAutoLoadedDefaultSource = true
                await autoLoadDefaultCTIfAvailable()
            }
        }
    }

    // MARK: - Tool Bar

    @ViewBuilder
    private var toolBar: some View {
        HStack(spacing: 12) {
            Button(action: browseForVolumeSource) {
                Label("Load Image", systemImage: "folder")
            }
            .disabled(viewModel.isRunning)

            Button(action: {
                viewModel.loadDefaultCTSample()
                Task { await runRealVolumetricRoundTrip() }
            }) {
                Label("Default CT", systemImage: "cross.case")
            }
            .disabled(viewModel.isRunning)

            Button(action: {
                Task { await runRealVolumetricRoundTrip() }
            }) {
                Label("Run Test", systemImage: "play.fill")
            }
            .disabled(viewModel.isRunning || viewModel.originalVolume == nil)

            Button(action: {
                viewModel.clearResults()
            }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled((viewModel.originalVolume == nil && viewModel.sliceMetrics.isEmpty) || viewModel.isRunning)

            Spacer()

            if viewModel.isRunning {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume Source")
                        .font(.headline)
                    Text(viewModel.sourceName)
                        .font(.subheadline)
                    Text("\(viewModel.volumeWidth)×\(viewModel.volumeHeight)×\(viewModel.volumeDepth)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if viewModel.isDefaultCTLoaded {
                        Text("Default CT sample active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Anatomical Plane")
                        .font(.headline)
                    Picker(
                        "Plane",
                        selection: Binding(
                            get: { viewModel.selectedPlane },
                            set: { newPlane in
                                viewModel.selectPlane(newPlane)
                                Task { await viewModel.runVolumetricTest(session: session) }
                            }
                        )
                    ) {
                        ForEach(VolumetricPlane.allCases, id: \.self) { plane in
                            Text(plane.rawValue).tag(plane)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Slice Navigator")
                        .font(.headline)
                    HStack {
                        Text("Slice")
                            .font(.caption)
                        Spacer()
                        Text("\(viewModel.currentSliceIndex + 1) / \(viewModel.totalSlices)")
                            .font(.caption.monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.currentSliceIndex) },
                            set: { viewModel.setCurrentSliceIndex(Int($0)) }
                        ),
                        in: 0...Double(max(viewModel.totalSlices - 1, 1)),
                        step: 1
                    )

                    HStack(spacing: 8) {
                        Button(action: { viewModel.setCurrentSliceIndex(viewModel.currentSliceIndex - 1) }) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.currentSliceIndex == 0)

                        Spacer()

                        Button(action: {
                            viewModel.setCurrentSliceIndex(viewModel.currentSliceIndex + 1)
                        }) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.currentSliceIndex >= viewModel.totalSlices - 1)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Wavelet Parameters")
                        .font(.headline)

                    Stepper(
                        "Z-axis Levels: \(viewModel.zDecompositionLevels)",
                        value: $viewModel.zDecompositionLevels,
                        in: 1...6
                    )
                    .font(.caption)

                    Picker("Wavelet", selection: $viewModel.waveletType) {
                        Text("5/3 (lossless)").tag("5/3 (lossless)")
                        Text("9/7 (lossy)").tag("9/7 (lossy)")
                        Text("Haar").tag("Haar")
                    }
                    .pickerStyle(.radioGroup)
                    .font(.caption)
                }

                Divider()

                Toggle("Show Difference Overlay", isOn: $viewModel.showDifferenceImage)
                    .font(.caption)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.originalVolume == nil && viewModel.sliceMetrics.isEmpty {
            ContentUnavailableView {
                Label("No Volumetric Data", systemImage: "cube.transparent")
            } description: {
                Text("Load an image or CT series, or use the default CT sample to inspect real voxel-based slice rendering.")
            }
        } else {
            VSplitView {
                sliceComparison
                    .frame(minHeight: 220)

                if viewModel.sliceMetrics.isEmpty {
                    VStack {
                        Text("Real voxel volume loaded")
                            .font(.headline)
                        Text("Click Run Test to perform a JP3D round-trip and compute per-slice metrics.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    qualityMetricsTable
                        .frame(minHeight: 120)
                }
            }
        }
    }

    // MARK: - Slice Comparison View

    @ViewBuilder
    private var sliceComparison: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Slice Comparison — \(viewModel.selectedPlane.rawValue) \(viewModel.currentSliceIndex + 1)")
                    .font(.headline)
                Spacer()

                if let slice = currentDisplaySlice {
                    Label(String(format: "%.1f dB", slice.psnr), systemImage: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(String(format: "%.4f", slice.ssim), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack(spacing: 12) {
                slicePlaceholder(label: "Original")
                slicePlaceholder(label: viewModel.showDifferenceImage ? "Difference" : "Decoded")
            }
            .padding(.horizontal)
        }
    }

    private func slicePlaceholder(label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.08))

            if let image = renderedImage(for: label) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(10)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: label == "Difference" ? "minus.square" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Text(label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var currentDisplaySlice: VolumeSlice? {
        viewModel.sliceMetrics.first {
            $0.plane == viewModel.selectedPlane && $0.index == viewModel.currentSliceIndex
        }
    }

    // MARK: - Quality Metrics Table

    @ViewBuilder
    private var qualityMetricsTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Per-Slice Quality Metrics")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            metricsHeaderRow

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.sliceMetrics) { slice in
                        metricsRow(for: slice)
                        Divider()
                    }
                }
            }
        }
    }

    private var metricsHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Slice").font(.caption.bold()).frame(width: 50, alignment: .center)
            Text("Plane").font(.caption.bold()).frame(width: 70, alignment: .leading)
            Text("PSNR (dB)").font(.caption.bold()).frame(width: 90, alignment: .trailing)
            Text("SSIM").font(.caption.bold()).frame(width: 80, alignment: .trailing)
            Text("Decode (ms)").font(.caption.bold()).frame(width: 100, alignment: .trailing)
            Text("Size").font(.caption.bold()).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal)
    }

    private func metricsRow(for slice: VolumeSlice) -> some View {
        HStack(spacing: 0) {
            Text("\(slice.index + 1)")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .center)
            Text(slice.plane.rawValue)
                .font(.caption)
                .frame(width: 70, alignment: .leading)
            Text(String(format: "%.1f", slice.psnr))
                .font(.caption.monospacedDigit())
                .foregroundColor(slice.psnr >= 40 || !slice.psnr.isFinite ? Color.primary : Color.orange)
                .frame(width: 90, alignment: .trailing)
            Text(String(format: "%.4f", slice.ssim))
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Text(String(format: "%.2f", slice.decodeTimeMs))
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .trailing)
            Text("\(slice.width)×\(slice.height)")
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private func browseForVolumeSource() {
        let panel = NSOpenPanel()
        panel.title = "Select CT Series or Image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await loadVolumeSource(from: url, isDefaultCT: false) }
    }

    private func loadVolumeSource(from url: URL, isDefaultCT: Bool) async {
        do {
            let loaded = try makeVolumeSource(from: url)
            viewModel.loadVolume(loaded.volume, name: loaded.name, isDefaultCT: isDefaultCT)
            await runRealVolumetricRoundTrip()
        } catch {
            viewModel.statusMessage = "Volume load failed: \(error.localizedDescription)"
            viewModel.setDecodedVolume(nil)
        }
    }

    private func runRealVolumetricRoundTrip() async {
        guard let volume = viewModel.originalVolume else {
            await viewModel.runVolumetricTest(session: session)
            return
        }

        do {
            viewModel.isRunning = true
            viewModel.progress = 0
            viewModel.statusMessage = "Encoding \(viewModel.sourceName)…"

            let encoder = JP3DEncoder(configuration: makeEncoderConfiguration())
            await encoder.setProgressCallback { update in
                Task { @MainActor in
                    viewModel.progress = min(0.55, update.overallProgress * 0.55)
                    viewModel.statusMessage = "\(update.stage.rawValue)…"
                }
            }
            let encoded = try await encoder.encode(volume)

            let decoder = JP3DDecoder(configuration: .default)
            await decoder.setProgressCallback { update in
                Task { @MainActor in
                    viewModel.progress = 0.55 + min(0.45, update.overallProgress * 0.45)
                    viewModel.statusMessage = "\(update.stage.rawValue)…"
                }
            }
            let decoded = try await decoder.decode(encoded.data)
            viewModel.setDecodedVolume(decoded.volume)

            await viewModel.runVolumetricTest(session: session)
        } catch {
            viewModel.isRunning = false
            viewModel.progress = 0
            viewModel.statusMessage = "Volume test failed: \(error.localizedDescription)"
        }
    }

    private func makeEncoderConfiguration() -> JP3DEncoderConfiguration {
        let compressionMode: JP3DCompressionMode
        switch viewModel.waveletType {
        case "9/7 (lossy)":
            compressionMode = .visuallyLossless
        case "Haar":
            compressionMode = .lossy(psnr: 42.0)
        default:
            compressionMode = .lossless
        }

        return JP3DEncoderConfiguration(
            compressionMode: compressionMode,
            tiling: .default,
            progressionOrder: .lrcps,
            qualityLayers: compressionMode == .lossless ? 1 : 3,
            levelsX: 3,
            levelsY: 3,
            levelsZ: viewModel.zDecompositionLevels,
            parallelEncoding: true
        )
    }

    private func autoLoadDefaultCTIfAvailable() async {
        if let url = defaultCTSeriesURL() {
            await loadVolumeSource(from: url, isDefaultCT: true)
        } else {
            viewModel.loadDefaultCTSample()
            await runRealVolumetricRoundTrip()
        }
    }

    private func renderedImage(for label: String) -> NSImage? {
        switch label {
        case "Original":
            return renderSliceImage(from: viewModel.originalVolume)
        case "Difference":
            return renderDifferenceImage()
        default:
            return renderSliceImage(from: viewModel.decodedVolume ?? viewModel.originalVolume)
        }
    }

    private func renderSliceImage(from volume: J2KVolume?) -> NSImage? {
        guard let volume else { return nil }
        let slice = sliceSamples(from: volume)
        return makeGrayscaleImage(from: slice.samples, width: slice.width, height: slice.height)
    }

    private func renderDifferenceImage() -> NSImage? {
        guard let originalVolume = viewModel.originalVolume else { return nil }
        let original = sliceSamples(from: originalVolume)
        let comparison = sliceSamples(from: viewModel.decodedVolume ?? originalVolume)
        guard original.width == comparison.width, original.height == comparison.height else { return nil }

        let differences = zip(original.samples, comparison.samples).map { min(abs($0 - $1) * 6.0, 255.0) }
        return makeDifferenceImage(from: differences, width: original.width, height: original.height)
    }

    private func sliceSamples(from volume: J2KVolume) -> (samples: [Float], width: Int, height: Int) {
        guard let component = volume.components.first else { return ([], 1, 1) }
        let width = volume.width
        let height = volume.height
        let depth = volume.depth

        func voxelValue(x: Int, y: Int, z: Int) -> Float {
            let linearIndex = ((z * height) + y) * width + x
            return sampleValue(at: linearIndex, in: component)
        }

        switch viewModel.selectedPlane {
        case .axial:
            let z = min(max(0, viewModel.currentSliceIndex), max(0, depth - 1))
            let samples = (0..<height).flatMap { y in
                (0..<width).map { x in voxelValue(x: x, y: y, z: z) }
            }
            return (samples, width, height)
        case .coronal:
            let y = min(max(0, viewModel.currentSliceIndex), max(0, height - 1))
            let samples = (0..<depth).flatMap { z in
                (0..<width).map { x in voxelValue(x: x, y: y, z: z) }
            }
            return (samples, width, depth)
        case .sagittal:
            let x = min(max(0, viewModel.currentSliceIndex), max(0, width - 1))
            let samples = (0..<depth).flatMap { z in
                (0..<height).map { y in voxelValue(x: x, y: y, z: z) }
            }
            return (samples, height, depth)
        }
    }

    private func sampleValue(at linearIndex: Int, in component: J2KVolumeComponent) -> Float {
        let bytesPerSample = max(1, component.bytesPerSample)
        let byteOffset = linearIndex * bytesPerSample
        guard byteOffset + bytesPerSample <= component.data.count else { return 0 }

        var rawValue = 0
        for byteIndex in 0..<bytesPerSample {
            rawValue |= Int(component.data[byteOffset + byteIndex]) << (8 * byteIndex)
        }

        if component.signed {
            let signBit = 1 << max(component.bitDepth - 1, 0)
            let fullRange = 1 << max(component.bitDepth, 1)
            if rawValue & signBit != 0 {
                rawValue -= fullRange
            }
        }

        return Float(rawValue)
    }

    private func makeGrayscaleImage(from samples: [Float], width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0, samples.count == width * height else { return nil }
        let minValue = samples.min() ?? 0
        let maxValue = samples.max() ?? 255
        let range = max(1, maxValue - minValue)

        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { rawBuffer in
            guard let output = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for index in 0..<samples.count {
                let normalized = UInt8(clamping: Int((((samples[index] - minValue) / range) * 255).rounded()))
                let offset = index * 4
                output[offset] = normalized
                output[offset + 1] = normalized
                output[offset + 2] = normalized
                output[offset + 3] = 255
            }
        }

        return makeImage(fromRGBA: rgba, width: width, height: height)
    }

    private func makeDifferenceImage(from samples: [Float], width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0, samples.count == width * height else { return nil }
        let maxValue = max(1, samples.max() ?? 1)

        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { rawBuffer in
            guard let output = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for index in 0..<samples.count {
                let normalized = UInt8(clamping: Int(((samples[index] / maxValue) * 255).rounded()))
                let offset = index * 4
                output[offset] = normalized
                output[offset + 1] = 0
                output[offset + 2] = 255 &- normalized
                output[offset + 3] = 255
            }
        }

        return makeImage(fromRGBA: rgba, width: width, height: height)
    }

    private func makeImage(fromRGBA rgba: Data, width: Int, height: Int) -> NSImage? {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let provider = CGDataProvider(data: rgba as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func makeVolumeSource(from url: URL) throws -> (name: String, volume: J2KVolume) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw J2KError.invalidParameter("Selected volume source does not exist")
        }

        if isDirectory.boolValue {
            let files = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { supportedVolumeExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            guard !files.isEmpty else {
                throw J2KError.invalidParameter("No supported slice files found in \(url.lastPathComponent)")
            }

            var sliceData: [Data] = []
            var sliceWidth = 0
            var sliceHeight = 0

            for file in files {
                let fileData = try Data(contentsOf: file)
                let (planar, width, height, componentCount) = try CodecService.imageParserFunction(fileData)

                if sliceWidth == 0 {
                    sliceWidth = width
                    sliceHeight = height
                }

                guard width == sliceWidth, height == sliceHeight else {
                    throw J2KError.invalidParameter("Slice dimensions in the selected series do not match")
                }

                sliceData.append(grayscalePlane(from: planar, pixelCount: width * height, componentCount: componentCount))
            }

            let combined = sliceData.reduce(into: Data(capacity: sliceWidth * sliceHeight * sliceData.count)) { partialResult, slice in
                partialResult.append(slice)
            }

            let component = J2KVolumeComponent(
                index: 0,
                bitDepth: 8,
                signed: false,
                width: sliceWidth,
                height: sliceHeight,
                depth: sliceData.count,
                data: combined
            )
            let volume = J2KVolume(
                width: sliceWidth,
                height: sliceHeight,
                depth: sliceData.count,
                components: [component],
                spacingX: 0.7,
                spacingY: 0.7,
                spacingZ: 1.25
            )
            let containsDICOM = files.contains { ["dcm", "dicom"].contains($0.pathExtension.lowercased()) }
            let name = containsDICOM ? "CT Series — \(url.lastPathComponent)" : "Image Stack — \(url.lastPathComponent)"
            return (name, volume)
        }

        let fileData = try Data(contentsOf: url)
        let (planar, width, height, componentCount) = try CodecService.imageParserFunction(fileData)
        let grayscale = grayscalePlane(from: planar, pixelCount: width * height, componentCount: componentCount)
        let component = J2KVolumeComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            depth: 1,
            data: grayscale
        )
        let volume = J2KVolume(width: width, height: height, depth: 1, components: [component])
        let ext = url.pathExtension.lowercased()
        let name = ["dcm", "dicom"].contains(ext) ? "CT Slice — \(url.lastPathComponent)" : "Image — \(url.lastPathComponent)"
        return (name, volume)
    }

    private func grayscalePlane(from planar: Data, pixelCount: Int, componentCount: Int) -> Data {
        guard componentCount >= 3, planar.count >= pixelCount * 3 else {
            return planar.prefix(pixelCount)
        }

        var grayscale = Data(count: pixelCount)
        planar.withUnsafeBytes { sourceBuffer in
            grayscale.withUnsafeMutableBytes { destinationBuffer in
                guard let source = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let destination = destinationBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                for index in 0..<pixelCount {
                    let r = Double(source[index])
                    let g = Double(source[pixelCount + index])
                    let b = Double(source[(pixelCount * 2) + index])
                    let luminance = UInt8(clamping: Int((0.299 * r + 0.587 * g + 0.114 * b).rounded()))
                    destination[index] = luminance
                }
            }
        }
        return grayscale
    }

    private func defaultCTSeriesURL() -> URL? {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let candidates = [
            workspaceRoot.appendingPathComponent("LocalDatasets/medical-dicom-organized/ct", isDirectory: true),
            workspaceRoot.appendingPathComponent("Examples/Medical/CT", isDirectory: true),
        ]

        for root in candidates where fileManager.fileExists(atPath: root.path) {
            if let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                let studyFolder = children.first { url in
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }
                return studyFolder ?? root
            }
            return root
        }

        return nil
    }

    private var supportedVolumeExtensions: Set<String> {
        ["dcm", "dicom", "png", "jpg", "jpeg", "tif", "tiff", "bmp", "pgm", "ppm"]
    }
}
#endif
