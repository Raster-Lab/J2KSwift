//
// BenchComponents.swift
// J2KBenchApp — v10.5 cross-silicon bench
//
// Shared SwiftUI building blocks used across the History / Run / Detail
// screens: the host-identity header, the per-fixture status badge, the
// compact fixture row, and the system share-sheet bridge.

import SwiftUI

// MARK: - Formatting

/// One decimal place, em-dash for missing values.
func msText(_ value: Double?) -> String {
    guard let value else { return "\u{2014}" }
    return String(format: "%.1f", value)
}

/// Human-readable byte count (e.g. "1.4 MB").
func byteText(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

// MARK: - Host header

/// Device identity strip shown at the top of the Run and Run-detail
/// screens. Takes plain strings so it serves both a live host and a
/// saved `HostSnapshot`.
struct HostHeader: View {
    let brand: String
    let detail: String      // "model · system version · N cores"
    let version: String     // J2KSwift semver

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(brand).font(.headline)
                Spacer()
                Text("J2KSwift v\(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status badge

/// Coloured capsule conveying a fixture's lifecycle state at a glance.
struct StatusBadge: View {
    let status: FixtureStatus

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }

    private var text: String {
        switch status {
        case .notSelected: return "Excluded"
        case .notRun:      return "Not run"
        case .running:     return "Running"
        case .done:        return "Done"
        case .failed:      return "Failed"
        }
    }
    private var symbol: String {
        switch status {
        case .notSelected: return "minus.circle"
        case .notRun:      return "circle.dotted"
        case .running:     return "hourglass"
        case .done:        return "checkmark.circle.fill"
        case .failed:      return "exclamationmark.triangle.fill"
        }
    }
    private var tint: Color {
        switch status {
        case .notSelected: return .secondary
        case .notRun:      return .secondary
        case .running:     return .blue
        case .done:        return .green
        case .failed:      return .red
        }
    }
}

// MARK: - Fixture row content

/// Compact, vertically-stacked fixture row — no horizontal scrolling.
/// Content only: the parent screen supplies the leading checkbox and
/// the `NavigationLink` wrapper.
struct FixtureRow: View {
    let fixture: BenchFixture
    let result: FixtureResult?
    let status: FixtureStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fixture.label).font(.subheadline.weight(.medium))
                Spacer()
                StatusBadge(status: status)
            }
            HStack(spacing: 12) {
                Text("\(fixture.width)\u{00d7}\(fixture.height) \u{00b7} \(fixture.bitDepth)-bit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let r = result {
                    metric("enc", r.encode.median)
                    metric("dec", r.fastestDecodeMedian)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func metric(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(msText(value)) ms")
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

// MARK: - Share sheet bridge

#if os(iOS)
import UIKit

/// Thin UIViewControllerRepresentable bridge so we can drive the
/// system share sheet from SwiftUI without pulling in a 3rd-party
/// package.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
