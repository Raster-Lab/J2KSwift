//
// ProgressIndicatorView.swift
// J2KSwift
//
// Progress indicator bar with per-stage breakdown.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

// MARK: - Progress Indicator View

/// Progress indicator with per-stage breakdown.
///
/// Shows overall progress and individual progress for each pipeline
/// stage (colour transform, DWT, quantise, entropy coding).
struct ProgressIndicatorView: View {
    /// Overall progress fraction (0.0 to 1.0).
    let overallProgress: Double
    /// Per-stage progress information.
    let stages: [StageProgress]
    /// Status message.
    let statusMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusMessage)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(overallProgress * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: overallProgress)
                .progressViewStyle(.linear)

            if !stages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(stages, id: \.stage) { stageProgress in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(stageProgress.isActive ? Color.blue : (stageProgress.progress >= 1.0 ? Color.green : Color.gray))
                                .frame(width: 8, height: 8)
                            Text(stageProgress.stage.rawValue)
                                .font(.caption)
                                .frame(width: 120, alignment: .leading)
                            ProgressView(value: stageProgress.progress)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: .infinity)
                            if let duration = stageProgress.duration {
                                Text(String(format: "%.1f ms", duration * 1000))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}
#endif
