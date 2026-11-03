import AppKit
import SwiftUI

/// Shares existing settings objects so reorganizing controls never migrates preferences.
struct AppSettingsView: View {
    @ObservedObject var service: BalanceService
    @ObservedObject var settings: AppSettings
    @State private var selection: String? = "settings.category.general"
    @State private var homeDraft = ""
    @State private var actionError: String?

    private let categories = [
        ("settings.category.general", "gearshape"),
        ("settings.category.account", "person.crop.circle"),
        ("settings.category.menu", "menubar.rectangle"),
        ("developer.title", "hammer"),
        ("about.title", "info.circle")
    ]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(categories, id: \.0) { key, symbol in
                    Label(L10n.string(key), systemImage: symbol).tag(key)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case "settings.category.menu":
                    PopoverCustomizationView(service: service, settings: settings)
                case "settings.category.account":
                    accountSettings
                case "developer.title":
                    DeveloperOptionsView(settings: settings, embedded: true)
                case "about.title":
                    AboutView(settings: settings, embedded: true)
                default:
                    generalSettings
                }
            }
            .navigationTitle(L10n.string(selection ?? "settings.category.general"))
        }
        .frame(minWidth: 760, minHeight: 600)
        .onAppear {
            homeDraft = settings.homePath
            settings.refreshLaunchAtLoginStatus()
        }
        .alert(L10n.string("settings.error_title"), isPresented: Binding(
            get: { settings.settingsError != nil || actionError != nil },
            set: { if !$0 { settings.clearSettingsError(); actionError = nil } }
        )) {
            Button(L10n.string("action.ok")) { settings.clearSettingsError(); actionError = nil }
            if settings.settingsDestination != nil {
                Button(L10n.string("action.open_system_settings")) {
                    settings.openRelevantSystemSettings()
                    settings.clearSettingsError()
                }
            }
        } message: {
            Text(settings.settingsError ?? actionError ?? "")
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                Picker(L10n.string("settings.language"), selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0; service.refresh() }
                )) {
                    ForEach(AppLanguage.allCases) { Text($0.localizedName).tag($0) }
                }
                Picker(L10n.string("settings.appearance"), selection: $settings.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { Text($0.localizedName).tag($0) }
                }
                Toggle(L10n.string("settings.launch_at_login"), isOn: Binding(
                    get: { settings.launchAtLoginEnabled }, set: { settings.setLaunchAtLogin($0) }
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
