//
// MainWindow.swift
// J2KSwift
//
// Main window with sidebar navigation and detail area.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - App Screen

/// Top-level navigation items that are not test categories.
enum AppScreen: String, CaseIterable, Identifiable {
    case report = "Report"
    case playlists = "Playlists"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .report:    return "chart.bar.doc.horizontal"
        case .playlists: return "list.bullet.rectangle"
        }
    }
}

/// Unified sidebar selection covering both test categories and app screens.
enum SidebarSelection: Hashable {
    case category(TestCategory)
    case screen(AppScreen)
}

// MARK: - Main Window View

/// Main window layout with sidebar navigation and detail area.
///
/// Uses `NavigationSplitView` to provide a sidebar listing test
/// categories and a detail area showing the selected category's
/// test interface. The toolbar contains global actions for running
/// all tests, stopping, exporting, and accessing settings.
struct MainWindowView: View {
    /// Main view model managing sidebar selection and global state.
    @State var viewModel: MainViewModel

    /// Whether the settings sheet is presented.
    @State private var showSettings: Bool = false

    /// Unified sidebar selection (category or app screen).
    @State private var sidebarSelection: SidebarSelection? = nil

    /// View model for the reporting dashboard.
    @State private var reportViewModel = ReportViewModel()

    /// View model for playlist management.
    @State private var playlistViewModel = PlaylistViewModel()

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .toolbar {
            toolbarContent
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: viewModel.session)
        }
    }

    // MARK: - Sidebar

    /// Sidebar listing all test categories with icons and counts.
    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $sidebarSelection) {
            Section("Tests") {
                ForEach(TestCategory.allCases) { category in
                    Label {
                        VStack(alignment: .leading) {
                            Text(category.displayName)
                                .font(.body)
                            Text(category.categoryDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: category.systemImage)
                            .foregroundStyle(.tint)
                    }
                    .tag(SidebarSelection.category(category))
                }
            }
            Section("Tools") {
                ForEach(AppScreen.allCases) { screen in
                    Label(screen.rawValue, systemImage: screen.systemImage)
                        .tag(SidebarSelection.screen(screen))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("J2KTestApp")
        .onChange(of: sidebarSelection) { _, newValue in
            if case .category(let cat) = newValue {
                viewModel.selectedCategory = cat
            } else {
                viewModel.selectedCategory = nil
            }
        }
    }

    // MARK: - Detail Area

    /// Detail view for the selected category or app screen.
    @ViewBuilder
    private var detailContent: some View {
        switch sidebarSelection {
        case .category(let category):
            CategoryDetailView(
                viewModel: viewModel.viewModel(for: category),
                session: viewModel.session
            )
        case .screen(let screen):
            switch screen {
            case .report:
                ReportView(viewModel: reportViewModel, session: viewModel.session)
            case .playlists:
                PlaylistView(viewModel: playlistViewModel, session: viewModel.session)
            }
        case nil:
            ContentUnavailableView {
                Label("Select a Category", systemImage: "sidebar.left")
            } description: {
                Text("Choose a test category from the sidebar to begin testing.")
            }
        }
    }

    // MARK: - Toolbar

    /// Toolbar with global actions.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: {
                Task { await viewModel.runAllTests() }
            }) {
                Label("Run All", systemImage: "play.fill")
            }
            .disabled(viewModel.isRunningAll)
            .help("Run all tests across all categories")
            .keyboardShortcut("r", modifiers: [.command])

            Button(action: {
                viewModel.stopAllTests()
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!viewModel.isRunningAll)
            .help("Stop all running tests")
            .keyboardShortcut(".", modifiers: [.command])
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button(action: {
                Task {
                    _ = await viewModel.exportResults(to: "test_results.json")
                }
            }) {
                Label("Export Results", systemImage: "square.and.arrow.up")
            }
            .help("Export test results as JSON")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button(action: {
                showSettings = true
            }) {
                Label("Settings", systemImage: "gear")
            }
            .help("Open application settings")
            .keyboardShortcut(",", modifiers: [.command])
        }

        ToolbarItem(placement: .status) {
            Text(viewModel.globalStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Performance Tab

/// Tab selection within the Performance category.
enum PerformanceTab: String, CaseIterable, Identifiable {
    /// Benchmark throughput and latency profiling.
    case benchmark = "Benchmark"
    /// GPU acceleration testing with Metal.
    case gpu = "GPU"
    /// SIMD vectorisation testing.
    case simd = "SIMD"

    var id: String { rawValue }
}

// MARK: - Streaming Tab

/// Tab selection within the Streaming category.
enum StreamingTab: String, CaseIterable, Identifiable {
    /// JPIP network streaming tests.
    case jpip = "JPIP"
    /// Motion JPEG 2000 frame playback tests.
    case mj2 = "MJ2"

    var id: String { rawValue }
}

// MARK: - Category Detail View

/// Detail view for a single test category.
///
/// Routes `.encode`, `.decode`, `.conformance`, `.validation`, `.performance`,
/// `.streaming`, and `.volumetric` to their dedicated GUI screens. Performance
/// uses tabbed sub-screens for Benchmark, GPU, and SIMD. Streaming uses tabbed
/// sub-screens for JPIP and MJ2.  All other categories fall back to the generic
/// results-table layout until their dedicated screens are implemented.
struct CategoryDetailView: View {
    /// View model for this category.
    @State var viewModel: TestCategoryViewModel

    /// The test session.
    let session: TestSession

    /// View model for the Encode screen.
    @State private var encodeViewModel = EncodeViewModel()
    /// View model for the Decode screen.
    @State private var decodeViewModel = DecodeViewModel()
    /// View model for the Round-Trip screen.
    @State private var roundTripViewModel = RoundTripViewModel()
    /// View model for the Conformance screen.
    @State private var conformanceViewModel = ConformanceViewModel()
    /// View model for the Interoperability screen.
    @State private var interopViewModel = InteropViewModel()
    /// View model for the Validation screen.
    @State private var validationViewModel = ValidationViewModel()
    /// View model for the Performance screen.
    @State private var performanceViewModel = PerformanceViewModel()
    /// View model for the GPU Testing screen.
    @State private var gpuTestViewModel = GPUTestViewModel()
    /// View model for the SIMD Testing screen.
    @State private var simdTestViewModel = SIMDTestViewModel()
    /// View model for the JPIP streaming screen.
    @State private var jpipViewModel = JPIPViewModel()
    /// View model for the MJ2 playback screen.
    @State private var mj2ViewModel = MJ2TestViewModel()
    /// View model for the JP3D volumetric screen.
    @State private var volumetricViewModel = VolumetricTestViewModel()

    /// Log messages for the console.
    @State private var logMessages: [LogMessage] = []

    /// Selected tab within the Performance screen.
    @State private var performanceTab: PerformanceTab = .benchmark
    /// Selected tab within the Streaming screen.
    @State private var streamingTab: StreamingTab = .jpip

    var body: some View {
        switch viewModel.category {
        case .encode:
            EncodeView(viewModel: encodeViewModel, session: session)
        case .decode:
            DecodeView(viewModel: decodeViewModel, session: session)
        case .conformance:
            ConformanceView(viewModel: conformanceViewModel, session: session)
        case .validation:
            ValidationView(viewModel: validationViewModel, session: session)
        case .performance:
            performanceDetailView
        case .streaming:
            streamingDetailView
        case .volumetric:
            VolumetricTestView(viewModel: volumetricViewModel, session: session)
        }
    }

    // MARK: - Performance Detail View (tabbed)

    @ViewBuilder
    private var performanceDetailView: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Performance Tab", selection: $performanceTab) {
                ForEach(PerformanceTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch performanceTab {
            case .benchmark:
                PerformanceView(viewModel: performanceViewModel, session: session)
            case .gpu:
                GPUTestView(viewModel: gpuTestViewModel, session: session)
            case .simd:
                SIMDTestView(viewModel: simdTestViewModel, session: session)
            }
        }
    }

    // MARK: - Streaming Detail View (tabbed)

    @ViewBuilder
    private var streamingDetailView: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Streaming Tab", selection: $streamingTab) {
                ForEach(StreamingTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            switch streamingTab {
            case .jpip:
                JPIPTestView(viewModel: jpipViewModel, session: session)
            case .mj2:
                MJ2TestView(viewModel: mj2ViewModel, session: session)
            }
        }
    }
}

// MARK: - Settings View

/// Settings sheet for application preferences.
struct SettingsView: View {
    let settings: TestSession

    @Environment(\.dismiss) private var dismiss
    @State private var localSettings = AppSettings()

    var body: some View {
        VStack(spacing: 16) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section("Encoding Defaults") {
                    HStack {
                        Text("Tile Size")
                        Spacer()
                        TextField("Width", value: $localSettings.defaultTileWidth, format: .number)
                            .frame(width: 60)
                        Text("×")
                        TextField("Height", value: $localSettings.defaultTileHeight, format: .number)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Quality")
                        Slider(value: $localSettings.defaultQuality, in: 0...1)
                        Text(String(format: "%.2f", localSettings.defaultQuality))
                            .monospacedDigit()
                            .frame(width: 40)
                    }

                    Stepper("Decomposition Levels: \(localSettings.defaultDecompositionLevels)",
                            value: $localSettings.defaultDecompositionLevels,
                            in: 0...10)

                    Stepper("Quality Layers: \(localSettings.defaultQualityLayers)",
                            value: $localSettings.defaultQualityLayers,
                            in: 1...20)

                    Toggle("HTJ2K by Default", isOn: $localSettings.defaultHTJ2K)
                    Toggle("GPU Acceleration by Default", isOn: $localSettings.defaultGPUAcceleration)
                }

                Section("Application") {
                    Toggle("Verbose Logging", isOn: $localSettings.verboseLogging)
                    Toggle("Auto-Run on File Drop", isOn: $localSettings.autoRunOnDrop)
                    Stepper("Recent Sessions: \(localSettings.maxRecentSessions)",
                            value: $localSettings.maxRecentSessions,
                            in: 1...50)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    Task {
                        await settings.updateSettings(localSettings)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450)
        .task {
            localSettings = await settings.settings
        }
    }
}
#endif
