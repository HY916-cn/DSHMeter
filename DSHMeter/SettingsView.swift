import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var service: BalanceService
    @ObservedObject var settings: AppSettings
    @State private var selection: String? = "general"
    @State private var homeDraft = ""
    private let sections = [
        ("general", "gearshape"),
        ("account", "person.crop.circle"),
        ("menu", "menubar.rectangle"),
        ("about", "info.circle")
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sections, id: \.0) { section, icon in
                    Label(L10n.string("settings." + section), systemImage: icon).tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case "account": accountSettings
                case "menu": menuSettings
                case "about": aboutSettings
                default: generalSettings
                }
            }
            .navigationTitle(L10n.string("settings." + (selection ?? "general")))
        }
        .frame(minWidth: 760, minHeight: 600)
        .onAppear { homeDraft = settings.homePath; settings.refreshLoginStatus() }
        .alert(L10n.string("error.title"), isPresented: Binding(
            get: { settings.settingsError != nil }, set: { if !$0 { settings.settingsError = nil } }
        )) { Button(L10n.string("action.ok")) { settings.settingsError = nil } }
        message: { Text(settings.settingsError ?? "") }
    }

    private var generalSettings: some View {
        Form {
            Section {
                Picker(L10n.string("settings.language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                Picker(L10n.string("settings.appearance"), selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text(L10n.string("appearance." + $0.rawValue)).tag($0) }
                }
                Toggle(L10n.string("settings.launch_at_login"), isOn: Binding(
                    get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private var accountSettings: some View {
        Form {
            Section(L10n.string("settings.credentials")) {
                Text(L10n.string("settings.credentials_help"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LabeledContent(L10n.string("settings.dsh_home")) {
                    TextField("~/.dsh", text: $homeDraft).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.string("settings.dsh_home"))
                }
                HStack {
                    Button(L10n.string("action.choose_folder"), action: chooseHome)
                    Spacer()
                    Button(L10n.string("action.apply")) { applyHome() }
                        .disabled(homeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button(L10n.string("action.open_dsh")) { ProjectLinks.openDSH() }
                Link(L10n.string("action.tutorial"), destination: ProjectLinks.tutorial)
            }
            Section(L10n.string("settings.refresh")) {
                Text(L10n.string("settings.refresh_help"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var menuSettings: some View {
        Form {
            Section {
                Text(L10n.string("settings.popover.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L10n.string("settings.popover.menu_bar_ring")) {
                Picker(L10n.string("settings.menu_style"), selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text(L10n.string("menu." + $0.rawValue)).tag($0) }
                }
                Picker(L10n.string("balance.currency"), selection: $settings.preferredCurrency) {
                    Text("CNY · ¥").tag("CNY")
                    Text("USD · $").tag("USD")
                }
                Text(L10n.string("settings.currency_help")).font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.popover.preview")) {
                MenuBarBalanceView(
                    title: service.menuBarTitle,
                    toppedUpPercent: service.selectedBalance?.toppedUpPercent,
                    grantedPercent: service.selectedBalance?.grantedPercent,
                    isStale: service.isStale,
                    style: settings.menuBarStyle
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .contain)
            }

            Section {
                Button(L10n.string("settings.popover.restore_defaults")) {
                    settings.menuBarStyle = .iconAndBalance
                    settings.preferredCurrency = "CNY"
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 580)
    }

    private var aboutSettings: some View {
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
        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identitySection: some View {
        GroupBox {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DSHMeter").font(.title2.weight(.semibold))
                    Text(String(format: L10n.string("about.version_format"), BundleInfo.version, BundleInfo.build))
                        .foregroundStyle(.secondary)
                    Text(L10n.string("about.description")).font(.callout).foregroundStyle(.secondary)
                    Link(L10n.string("action.tutorial"), destination: ProjectLinks.tutorial)
                    Link(destination: ProjectLinks.repository) {
                        Label(L10n.string("action.project"), systemImage: "link")
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
                Link(L10n.string("action.releases"), destination: ProjectLinks.repository.appendingPathComponent("releases"))
            }
            .padding(.top, 6)
        }
    }

    private var dataSection: some View {
        GroupBox(L10n.string("about.local_data")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(settings.homeURL.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text(L10n.string("about.local_data_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(L10n.string("action.platform"), destination: ProjectLinks.balancePage)
            }
            .padding(.top, 6)
        }
    }

    private var privacySection: some View {
        GroupBox(L10n.string("about.privacy")) {
            Text(L10n.string("about.privacy_help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private var licenseSection: some View {
        GroupBox(L10n.string("about.license")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("about.credits_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("CodexMeter · Raycal", destination: URL(string: "https://github.com/raycalrui/CodexMeter")!)
                Link("ClaudeMeter", destination: URL(string: "https://github.com/HY916-cn/ClaudeMeter")!)
                Link("Yams · MIT", destination: URL(string: "https://github.com/jpsim/Yams")!)
            }
            .padding(.top, 6)
        }
    }

    private func chooseHome() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = settings.homeURL
        if panel.runModal() == .OK, let url = panel.url { homeDraft = url.path; applyHome() }
    }

    private func applyHome() {
        let path = NSString(string: homeDraft.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard path.hasPrefix("/") else { settings.settingsError = L10n.string("settings.path_error"); return }
        if URL(fileURLWithPath: path).standardizedFileURL == settings.homeURL.standardizedFileURL {
            service.refresh()
            return
        }
        settings.homePath = path
        homeDraft = path
        service.changeHome()
    }
}
