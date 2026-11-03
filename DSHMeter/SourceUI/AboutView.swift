import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var settings: AppSettings
    var embedded = false
    @Environment(\.dismiss) private var dismiss

    private let repositoryURL = ProjectLinks.repository

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                header
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identitySection
                    updateSection
                    dataSection
                    privacySection
                    licenseSection
                }
                .padding(18)
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Label(L10n.string("about.title"), systemImage: "info.circle")
                .font(.headline)
            Spacer()
            Button(L10n.string("action.close")) { dismiss() }
        }
        .padding(16)
    }

    private var identitySection: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DSHMeter").font(.title2.weight(.semibold))
                    Text(L10n.format(
                        "about.version_format",
                        BundleInfo.version,
                        BundleInfo.build
                    ))
                    .foregroundStyle(.secondary)
                    Link(L10n.string("action.open_setup_readme"), destination: ProjectLinks.tutorial)
                    Link(destination: repositoryURL) {
                        Label(L10n.string("about.github"), systemImage: "link")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var updateSection: some View {
        GroupBox(L10n.string("updates.title")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("updates.github_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                updateStatus
            }
            .padding(.top, 6)
        }
    }

    private var updateStatus: some View {
        Link(
            L10n.string("updates.open_release"),
            destination: repositoryURL.appendingPathComponent("releases")
        )
    }

    private var dataSection: some View {
        GroupBox(L10n.string("about.local_data")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(settings.homeURL.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button(L10n.string("about.reveal_data")) {
                    let target = FileManager.default.fileExists(atPath: settings.homeURL.path)
                        ? settings.homeURL
                        : settings.homeURL.deletingLastPathComponent()
                    NSWorkspace.shared.activateFileViewerSelecting([target])
                }
            }
            .padding(.top, 6)
        }
    }

    private var privacySection: some View {
        GroupBox(L10n.string("about.privacy")) {
            Text(L10n.string("about.privacy_description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private var licenseSection: some View {
        GroupBox(L10n.string("about.license")) {
            Text(L10n.string("about.license_undeclared"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}
