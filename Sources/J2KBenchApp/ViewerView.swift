//
// ViewerView.swift
// J2KBenchApp — image viewer
//
// The "Viewer" tab. A chooser for the three image sources — open a
// JPEG 2000 file, render a benchmark fixture, or round-trip a photo.
// Loading a source decodes it and pushes `ImageDetailView`.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ViewerView: View {
    @StateObject private var model = ViewerModel()

    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var roundTripQuality: RoundTripQuality = .lossless

    /// Allowed import types. JPEG 2000 has a system UTI only for
    /// `.jp2`, and DICOM for `.dcm`; raw `.j2k`/`.jph` codestreams have
    /// none — so `.data` is included to keep every file selectable.
    /// `ViewerModel` validates the actual format after the pick.
    private static let j2kContentTypes: [UTType] = {
        var types: [UTType] = [.data]
        if let dicom = UTType("org.nema.dicom") { types.insert(dicom, at: 0) }
        if let jp2 = UTType("public.jpeg-2000") { types.insert(jp2, at: 0) }
        return types
    }()

    var body: some View {
        NavigationStack {
            List {
                introSection
                sourceSection
                if model.isLoading { loadingSection }
                if let error = model.errorMessage { errorSection(error) }
            }
            .navigationTitle("Image Viewer")
            .navigationDestination(item: $model.current) { image in
                ImageDetailView(image: image)
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: Self.j2kContentTypes,
                          onCompletion: handleFileImport)
            .onChange(of: photoItem) { _, newItem in
                guard let item = newItem else { return }
                photoItem = nil
                Task { await model.loadPhoto(item, quality: roundTripQuality) }
            }
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            Text("Decode and view a JPEG 2000 image with J2KSwift. "
                 + "Open a file, render one of the benchmark fixtures, or "
                 + "round-trip a photo through the codec.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var sourceSection: some View {
        Section("Choose an image") {
            // 1 — bundled real medical image
            Menu {
                ForEach(MedicalSample.all) { sample in
                    Button(sample.menuLabel) {
                        Task { await model.loadMedical(sample) }
                    }
                }
            } label: {
                SourceRow(symbol: "cross.case", title: "Medical Image",
                          subtitle: "A real CT / MR / X-ray, decoded by J2KSwift")
            }
            .disabled(model.isLoading)

            // 2 — benchmark fixture
            Menu {
                ForEach(BenchModel.corpus) { fixture in
                    Button(fixture.label) {
                        Task { await model.loadFixture(fixture) }
                    }
                }
            } label: {
                SourceRow(symbol: "square.grid.2x2", title: "Benchmark Fixture",
                          subtitle: "Synthesise, encode and decode a corpus fixture")
            }
            .disabled(model.isLoading)

            // 3 — photo round-trip
            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    SourceRow(symbol: "photo.on.rectangle",
                              title: "Round-trip a Photo",
                              subtitle: "Encode a photo to HT-J2K, decode it back")
                }
                .disabled(model.isLoading)

                Picker("Quality", selection: $roundTripQuality) {
                    ForEach(RoundTripQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isLoading)
            }

            // 4 — open a file (advanced; last)
            Button { showFileImporter = true } label: {
                SourceRow(symbol: "doc.badge.plus", title: "Open a File",
                          subtitle: "JPEG 2000 (.jp2 / .j2k / .jph) or "
                                  + "uncompressed DICOM (.dcm)")
            }
            .disabled(model.isLoading)
        }
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(model.statusText).font(.callout)
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task { await model.loadFile(url) }
        case .failure(let error):
            model.errorMessage = error.localizedDescription
        }
    }
}

/// A tappable source row — its own `View` so it can be used inside the
/// `Menu` / `PhotosPicker` label builders without main-actor isolation
/// friction.
private struct SourceRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
