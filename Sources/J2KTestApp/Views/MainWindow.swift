//
// MainWindow.swift
// J2KSwift
//
// Main window with sidebar navigation and detail area.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

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
        List(TestCategory.allCases, selection: $viewModel.selectedCategory) { category in
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
            .tag(category)
        }
        .listStyle(.sidebar)
        .navigationTitle("J2KTestApp")
    }

    // MARK: - Detail Area

    /// Detail view for the selected category.
    @ViewBuilder
    private var detailContent: some View {
        if let category = viewModel.selectedCategory {
            CategoryDetailView(
                viewModel: viewModel.viewModel(for: category),
                session: viewModel.session
            )
        } else {
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

// MARK: - Category Detail View

/// Detail view for a single test category.
///
/// Routes `.encode`, `.decode`, and the round-trip sub-task to their
/// dedicated GUI screens. All other categories fall back to the generic
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

    /// Log messages for the console.
    @State private var logMessages: [LogMessage] = []

    var body: some View {
        switch viewModel.category {
        case .encode:
            EncodeView(viewModel: encodeViewModel, session: session)
        case .decode:
            DecodeView(viewModel: decodeViewModel, session: session)
        default:
            genericDetailView
        }
    }

    // MARK: - Generic Detail View (fallback for other categories)

    @ViewBuilder
    private var genericDetailView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(viewModel.category.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(viewModel.category.categoryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button(action: {
                    Task { await viewModel.startTests(session: session) }
                }) {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(viewModel.isRunning)
                .keyboardShortcut(.return, modifiers: [.command])

                Button(action: {
                    viewModel.clearResults()
                }) {
                    Label("Clear", systemImage: "trash")
                }
            }
            .padding()

            Divider()

            // Progress
            if viewModel.isRunning || viewModel.progress > 0 {
                ProgressIndicatorView(
                    overallProgress: viewModel.progress,
                    stages: [],
                    statusMessage: viewModel.statusMessage
                )
            }

            // Results table
            if !viewModel.results.isEmpty {
                ResultsTableView(
                    results: viewModel.results,
                    selectedResult: $viewModel.selectedResult
                )
                .frame(minHeight: 200)
            } else {
                ContentUnavailableView {
                    Label("No Results", systemImage: "tray")
                } description: {
                    Text("Run tests to see results here.")
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            // Log console
            LogConsoleView(messages: logMessages)
                .frame(height: 150)
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
