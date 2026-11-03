import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var service: BalanceService
    @ObservedObject var settings: AppSettings
    @State private var selection: String? = "general"
    @State private var homeDraft = ""
    private let sections = [("general", "gearshape"), ("menu", "menubar.rectangle"), ("about", "info.circle")]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sections, id: \.0) { section, icon in
                    Label(L10n.string("settings." + section), systemImage: icon).tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 210)
        } detail: {
            Form {
                switch selection {
                case "menu": menuSettings
                case "about": aboutSettings
                default: generalSettings
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string("settings." + (selection ?? "general")))
        }
        .frame(minWidth: 680, minHeight: 520)
        .onAppear { homeDraft = settings.homePath; settings.refreshLoginStatus() }
        .alert(L10n.string("error.title"), isPresented: Binding(
            get: { settings.settingsError != nil }, set: { if !$0 { settings.settingsError = nil } }
        )) { Button(L10n.string("action.ok")) { settings.settingsError = nil } }
        message: { Text(settings.settingsError ?? "") }
    }

    private var generalSettings: some View {
        Group {
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
            Section(L10n.string("settings.refresh")) {
                Text(L10n.string("settings.refresh_help"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var menuSettings: some View {
        Section(L10n.string("settings.menu")) {
            Picker(L10n.string("settings.menu_style"), selection: $settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { Text(L10n.string("menu." + $0.rawValue)).tag($0) }
            }
            Picker(L10n.string("balance.currency"), selection: $settings.preferredCurrency) {
                Text("CNY · ¥").tag("CNY")
                Text("USD · $").tag("USD")
            }
            Text(L10n.string("settings.currency_help")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var aboutSettings: some View {
        Group {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DSHMeter").font(.title2.bold())
                        Text("0.1.0").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(L10n.string("about.description")).font(.callout)
                Link(L10n.string("action.project"), destination: ProjectLinks.repository)
                Link(L10n.string("action.tutorial"), destination: ProjectLinks.tutorial)
                Link(L10n.string("action.releases"), destination: ProjectLinks.repository.appendingPathComponent("releases"))
                Link(L10n.string("action.platform"), destination: ProjectLinks.balancePage)
            }
            Section(L10n.string("about.privacy")) {
                Text(L10n.string("about.privacy_help")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.string("about.credits")) {
                Text(L10n.string("about.credits_help")).font(.caption).foregroundStyle(.secondary)
                Link("CodexMeter · Raycal", destination: URL(string: "https://github.com/raycalrui/CodexMeter")!)
                Link("ClaudeMeter", destination: URL(string: "https://github.com/HY916-cn/ClaudeMeter")!)
                Link("Yams · MIT", destination: URL(string: "https://github.com/jpsim/Yams")!)
            }
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
