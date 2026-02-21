//
// J2KTestApp.swift
// J2KSwift
//
// SwiftUI macOS application for testing all J2KSwift features.
//

import Foundation
import J2KCore

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - J2KTestApp

/// J2KTestApp — a native macOS GUI application for testing J2KSwift.
///
/// Provides a complete graphical environment for testing every feature
/// of the JPEG 2000 implementation including encoding, decoding,
/// conformance, performance, streaming, and volumetric workflows.
@main
struct J2KTestApp: App {
    /// The shared view model managing global test state.
    @State private var viewModel = MainViewModel()

    /// Window preferences for persisting size and sidebar selection.
    @State private var windowPreferences = WindowPreferences()

    var body: some Scene {
        // MARK: Main Window
        WindowGroup {
            MainWindowView(viewModel: viewModel, windowPreferences: windowPreferences)
        }
        .defaultSize(
            width: windowPreferences.savedWidth,
            height: windowPreferences.savedHeight
        )
        .commands {
            // Remove the default New Item menu entry
            CommandGroup(replacing: .newItem) {}

            // Tests menu
            CommandMenu("Tests") {
                Button("Run All Tests") {
                    Task { await viewModel.runAllTests() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.isRunningAll)

                Button("Stop All Tests") {
                    viewModel.stopAllTests()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!viewModel.isRunningAll)

                Divider()

                ForEach(TestCategory.allCases) { category in
                    Button("Run \(category.displayName) Tests") {
                        viewModel.selectedCategory = category
                        Task {
                            await viewModel.viewModel(for: category).startTests(session: viewModel.session)
                        }
                    }
                }
            }

            // Help → About
            CommandGroup(replacing: .appInfo) {
                Button("About J2KTestApp") {
                    NSApp.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "J2KTestApp",
                            NSApplication.AboutPanelOptionKey.applicationVersion: getVersion(),
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "© 2026 Raster Lab. All rights reserved.\n\nA native macOS GUI application for testing the J2KSwift JPEG 2000 framework."
                            ),
                        ]
                    )
                }
            }
        }

        // MARK: Settings Scene (macOS 13+)
        Settings {
            SettingsSceneView()
        }
    }
}

// MARK: - Settings Scene View

/// Top-level settings view shown in the Settings scene (⌘,).
private struct SettingsSceneView: View {
    @State private var localSettings = AppSettings()
    private let session = TestSession()

    var body: some View {
        Form {
            Section("Encoding Defaults") {
                HStack {
                    Text("Tile Size")
                    Spacer()
                    TextField("Width", value: $localSettings.defaultTileWidth, format: .number)
                        .frame(width: 70)
                    Text("×")
                    TextField("Height", value: $localSettings.defaultTileHeight, format: .number)
                        .frame(width: 70)
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
        .frame(minWidth: 400, minHeight: 360)
        .task {
            localSettings = await session.settings
        }
    }
}

#else

// MARK: - Non-macOS Fallback

/// On non-macOS platforms, J2KTestApp is not available.
/// The GUI application requires macOS with SwiftUI support.
@main
struct J2KTestAppFallback {
    static func main() {
        print("J2KTestApp requires macOS with SwiftUI support.")
        print("Use the j2k command-line tool for non-macOS platforms.")
    }
}
#endif
