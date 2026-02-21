//
// LogConsoleView.swift
// J2KSwift
//
// Log console panel showing real-time encoder/decoder output.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Log Console View

/// Log console panel showing real-time encoder/decoder output.
///
/// Displays timestamped log messages with colour-coded severity levels.
/// Supports filtering by log level and clearing the console.
struct LogConsoleView: View {
    /// Log messages to display.
    let messages: [LogMessage]

    /// Minimum log level to display.
    @State private var minimumLevel: LogLevel = .info

    /// Whether to auto-scroll to the latest message.
    @State private var autoScroll: Bool = true

    /// Filtered messages based on minimum level.
    private var filteredMessages: [LogMessage] {
        messages.filter { $0.level >= minimumLevel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Toolbar
            HStack {
                Text("Console")
                    .font(.headline)
                Spacer()

                Picker("Level", selection: $minimumLevel) {
                    Text("Debug").tag(LogLevel.debug)
                    Text("Info").tag(LogLevel.info)
                    Text("Warning").tag(LogLevel.warning)
                    Text("Error").tag(LogLevel.error)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 8)

            Divider()

            // Log messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredMessages) { message in
                            logRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: filteredMessages.count) { _, _ in
                    if autoScroll, let lastID = filteredMessages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .font(.system(.body, design: .monospaced))
    }

    /// Creates a row for a single log message.
    @ViewBuilder
    private func logRow(_ message: LogMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeFormatter.string(from: message.timestamp))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(message.level.rawValue)
                .fontWeight(.medium)
                .foregroundStyle(levelColour(message.level))
                .frame(width: 60, alignment: .leading)

            Text(message.message)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 1)
    }

    /// Returns the colour for a log level.
    private func levelColour(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    /// Time formatter for log timestamps.
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}
#endif
