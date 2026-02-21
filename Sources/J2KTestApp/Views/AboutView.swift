//
// AboutView.swift
// J2KSwift
//
// Application icon and About screen.
//

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import J2KCore

/// The About screen showing the application icon, version, copyright, and links.
///
/// Displayed as a separate `Window` scene in `J2KTestApp` and can also be
/// shown as a sheet from the Help menu.
struct AboutView: View {
    /// Data for the about screen.
    let viewModel: AboutViewModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: J2KDesignSystem.spacingLG) {
            // App icon placeholder (uses SF Symbols until a real icon is supplied)
            Image(systemName: "square.stack.3d.up.fill")
                .resizable()
                .scaledToFit()
                .frame(width: J2KDesignSystem.iconSizeXL, height: J2KDesignSystem.iconSizeXL)
                .foregroundStyle(.blue.gradient)
                .accessibilityLabel("J2KTestApp icon")

            VStack(spacing: J2KDesignSystem.spacingSM) {
                Text(viewModel.appName)
                    .font(J2KDesignSystem.headlineFont)
                    .accessibilityIdentifier(AccessibilityIdentifiers.aboutVersionLabel)

                Text("Version \(viewModel.version)")
                    .font(J2KDesignSystem.bodyFont)
                    .foregroundStyle(.secondary)

                Text(viewModel.copyright)
                    .font(J2KDesignSystem.captionFont)
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.tagline)
                .font(J2KDesignSystem.bodyFont)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Divider()

            // Links
            HStack(spacing: J2KDesignSystem.spacingMD) {
                Button("Repository") {
                    openURL(viewModel.repositoryURL)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier(AccessibilityIdentifiers.aboutRepoLink)

                Text("·").foregroundStyle(.secondary)

                Button("Documentation") {
                    openURL(viewModel.documentationURL)
                }
                .buttonStyle(.link)
            }

            // Acknowledgements
            GroupBox("Acknowledgements") {
                VStack(alignment: .leading, spacing: J2KDesignSystem.spacingXS) {
                    ForEach(viewModel.acknowledgements, id: \.self) { item in
                        Text("• \(item)")
                            .font(J2KDesignSystem.captionFont)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(J2KDesignSystem.spacingXS)
            }
        }
        .padding(J2KDesignSystem.spacingXL)
        .frame(width: 400)
        .fixedSize()
    }
}

#if DEBUG
#Preview {
    AboutView(viewModel: AboutViewModel())
}
#endif
#endif
