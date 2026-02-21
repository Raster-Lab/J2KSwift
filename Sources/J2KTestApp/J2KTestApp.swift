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
    /// The shared test session for the application.
    @State private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {}

            // Test menu
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
