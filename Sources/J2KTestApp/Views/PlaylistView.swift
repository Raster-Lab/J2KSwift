//
// PlaylistView.swift
// J2KSwift
//
// Playlist management for creating, saving, and running test playlists.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// Playlist management screen for creating, saving, and running test playlists.
struct PlaylistView: View {
    @State var viewModel: PlaylistViewModel
    let session: TestSession

    @State private var showCreateSheet: Bool = false
    @State private var newPlaylistName: String = ""
    @State private var newPlaylistCategories: Set<TestCategory> = []

    var body: some View {
        HSplitView {
            // Sidebar: playlist list
            VStack(spacing: 0) {
                List(selection: $viewModel.selectedPlaylist) {
                    Section("Presets") {
                        ForEach(viewModel.playlists.filter { isPreset($0) }) { entry in
                            playlistRow(entry)
                        }
                    }
                    Section("Custom") {
                        ForEach(viewModel.playlists.filter { !isPreset($0) }) { entry in
                            playlistRow(entry)
                        }
                        .onMove { src, dst in viewModel.movePlaylist(from: src, to: dst) }
                        .onDelete { idx in
                            let customs = viewModel.playlists.filter { !isPreset($0) }
                            idx.forEach { viewModel.deletePlaylist(customs[$0]) }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()

                Button(action: { showCreateSheet = true }) {
                    Label("New Playlist", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 260)

            // Detail: selected playlist
            if let selected = viewModel.selectedPlaylist {
                playlistDetail(selected)
            } else {
                ContentUnavailableView {
                    Label("No Playlist Selected", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Select a playlist from the sidebar to view its details and run it.")
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar { toolbarContent }
        .onAppear { viewModel.loadPresets() }
        .sheet(isPresented: $showCreateSheet) {
            createPlaylistSheet
        }
    }

    // MARK: - Playlist Row

    @ViewBuilder
    private func playlistRow(_ entry: PlaylistEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
                .font(.body)
            Text("\(entry.categories.count) categories")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(entry)
    }

    // MARK: - Playlist Detail

    @ViewBuilder
    private func playlistDetail(_ entry: PlaylistEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Created: \(entry.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Categories")
                .font(.headline)

            ForEach(entry.categories, id: \.self) { category in
                Label {
                    VStack(alignment: .leading) {
                        Text(category.displayName)
                        Text(category.categoryDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: category.systemImage)
                        .foregroundStyle(.tint)
                }
            }

            Spacer()

            if viewModel.isRunning {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.progress) {
                        Text("Running…")
                            .font(.caption)
                    }
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(action: {
                    Task { await viewModel.runPlaylist(entry, session: session) }
                }) {
                    Label("Run Playlist", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Create Sheet

    @ViewBuilder
    private var createPlaylistSheet: some View {
        VStack(spacing: 16) {
            Text("New Playlist")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("Name") {
                    TextField("Playlist name", text: $newPlaylistName)
                }
                Section("Categories") {
                    ForEach(TestCategory.allCases) { cat in
                        Toggle(cat.displayName, isOn: Binding(
                            get: { newPlaylistCategories.contains(cat) },
                            set: { on in
                                if on { newPlaylistCategories.insert(cat) }
                                else { newPlaylistCategories.remove(cat) }
                            }
                        ))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { showCreateSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    if !newPlaylistName.isEmpty {
                        _ = viewModel.createPlaylist(name: newPlaylistName, categories: Array(newPlaylistCategories))
                        newPlaylistName = ""
                        newPlaylistCategories = []
                        showCreateSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPlaylistName.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showCreateSheet = true }) {
                Label("New Playlist", systemImage: "plus")
            }
            .help("Create a new playlist")
        }
    }

    // MARK: - Helpers

    private func isPreset(_ entry: PlaylistEntry) -> Bool {
        PlaylistPreset.allCases.map(\.rawValue).contains(entry.name)
    }
}
#endif
