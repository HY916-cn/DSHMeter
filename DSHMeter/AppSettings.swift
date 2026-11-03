import AppKit
import Combine
import DSHMeterCore
import Foundation
import ServiceManagement
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans = "zh-Hans", zhHant = "zh-Hant"
    var id: String { rawValue }
    var localizedName: String { title }
    var title: String {
        switch self {
        case .system: return L10n.string("language.system")
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// A nil preference lets each app window track the current system appearance.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// MenuBarExtra's AppKit window does not always honor SwiftUI's color-scheme preference.
    var windowAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    var localizedName: String {
        L10n.string("settings.appearance.\(rawValue)")
    }
}

enum SettingsDestination: Equatable {
    /// Identifies the System Settings pane that can resolve the latest error.
    case notifications
    case loginItems
}

extension MenuBarDisplayStyle {
    var localizedName: String {
        switch self {
        case .progressAndPercentage:
            return L10n.string("settings.style.progress_percentage")
        case .horizontalBarBesidePercentage:
            return L10n.string("settings.style.bar_beside")
        case .compactBarBelowPercentage:
            return L10n.string("settings.style.bar_below")
        case .dualBars:
            return L10n.string("settings.style.dual_bars")
        case .percentageOnly:
            return L10n.string("settings.style.percentage")
        case .progressOnly:
            return L10n.string("settings.style.progress")
        }
    }
}

extension MenuBarFontWeightChoice {
    var localizedName: String {
        L10n.string("developer.font_weight.\(rawValue)")
    }
}

extension MenuBarColorChoice {
    var localizedName: String {
        L10n.string("developer.color_choice.\(rawValue)")
    }
}

extension StaleIndicatorPlacement {
    var localizedName: String {
        L10n.string("developer.stale_placement.\(rawValue)")
    }
}

extension DeveloperPreviewPreset {
    var localizedName: String {
        L10n.string("developer.preset.\(rawValue)")
    }
}

extension PopoverContentSection {
    var localizedName: String {
        L10n.string("settings.popover.section.\(rawValue)")
    }
}

enum BundleInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.3" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "4" }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var homePath: String { didSet { defaults.set(homePath, forKey: "dsh.home") } }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language"); L10n.language = language }
    }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var preferredCurrency: String { didSet { defaults.set(preferredCurrency, forKey: "balance.currency") } }
    @Published var referenceBalances: [String: String] = [:] {
        didSet { defaults.set(referenceBalances, forKey: "balance.references") }
    }
    @Published var launchAtLogin = false
    @Published var settingsError: String?
    @Published var settingsDestination: SettingsDestination?

    var appearanceMode: AppAppearanceMode {
        get { AppAppearanceMode(rawValue: appearance.rawValue) ?? .system }
        set { appearance = AppAppearance(rawValue: newValue.rawValue) ?? .system }
    }

    var launchAtLoginEnabled: Bool { launchAtLogin }

    @Published var menuBarStyle: MenuBarDisplayStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    @Published var popoverContent: PopoverContentConfiguration {
        didSet {
            let normalized = popoverContent.normalized()
            if normalized != popoverContent {
                popoverContent = normalized
                return
            }
            if let data = try? JSONEncoder().encode(normalized) {
                defaults.set(data, forKey: Keys.popoverContent)
            }
        }
    }

    @Published var developerAppearance: MenuBarAppearance {
        didSet {
            let normalized = developerAppearance.normalized()
            if normalized != developerAppearance {
                developerAppearance = normalized
                return
            }
            if let data = try? JSONEncoder().encode(normalized) {
                defaults.set(data, forKey: Keys.developerAppearance)
            }
        }
    }

    @Published var developerPreviewEnabled: Bool {
        didSet { defaults.set(developerPreviewEnabled, forKey: Keys.developerPreviewEnabled) }
    }

    @Published var developerPreviewPreset: DeveloperPreviewPreset {
        didSet { defaults.set(developerPreviewPreset.rawValue, forKey: Keys.developerPreviewPreset) }
    }

    @Published private(set) var developerPreviewRemainingPercent: Double {
        didSet {
            defaults.set(
                developerPreviewRemainingPercent,
                forKey: Keys.developerPreviewRemainingPercent
            )
        }
    }

    @Published private(set) var developerPreviewRemainingTimePercent: Double {
        didSet {
            defaults.set(
                developerPreviewRemainingTimePercent,
                forKey: Keys.developerPreviewRemainingTimePercent
            )
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let menuBarStyle = "menu.style"
        static let popoverContent = "popover.contentConfiguration"
        static let developerAppearance = "developer.appearance"
        static let developerAppearanceDefaultsVersion = "developer.appearanceDefaultsVersion"
        static let developerPreviewEnabled = "developer.previewEnabled"
        static let developerPreviewPreset = "developer.previewPreset"
        static let developerPreviewRemainingPercent = "developer.previewRemainingPercent"
        static let developerPreviewRemainingTimePercent = "developer.previewRemainingTimePercent"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homePath = defaults.string(forKey: "dsh.home") ?? ProcessInfo.processInfo.environment["DSH_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh").path
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "system") ?? .system
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        preferredCurrency = defaults.string(forKey: "balance.currency") ?? "CNY"
        referenceBalances = defaults.dictionary(forKey: "balance.references") as? [String: String] ?? [:]
        let legacyStyleNames = [
            "iconAndBalance": MenuBarDisplayStyle.progressAndPercentage,
            "balanceOnly": .percentageOnly,
            "iconOnly": .progressOnly,
            "horizontalBarBesideBalance": .horizontalBarBesidePercentage,
            "compactBarBelowBalance": .compactBarBelowPercentage,
            "dualBars": .dualBars
        ]
        let storedStyle = defaults.string(forKey: Keys.menuBarStyle) ?? ""
        menuBarStyle = MenuBarDisplayStyle(rawValue: storedStyle)
            ?? legacyStyleNames[storedStyle] ?? .progressAndPercentage
        if let data = defaults.data(forKey: Keys.popoverContent),
           let decoded = try? JSONDecoder().decode(
               PopoverContentConfiguration.self,
               from: data
           ) {
            popoverContent = decoded.normalized()
        } else {
            popoverContent = .defaultValue
        }
        let appearanceDefaultsVersion = defaults.integer(
            forKey: Keys.developerAppearanceDefaultsVersion
        )
        if let data = defaults.data(forKey: Keys.developerAppearance),
           let decoded = try? JSONDecoder().decode(MenuBarAppearance.self, from: data) {
            var migrated = decoded
            if appearanceDefaultsVersion < 1 {
                migrated = migrated.migratingLegacyRingDefaults()
            }
            if appearanceDefaultsVersion < 2 {
                migrated = migrated.migratingLegacyTimeColor()
            }
            let normalized = migrated.normalized()
            developerAppearance = normalized

            if appearanceDefaultsVersion < 2,
               let migratedData = try? JSONEncoder().encode(normalized) {
                defaults.set(migratedData, forKey: Keys.developerAppearance)
            }
        } else {
            developerAppearance = .acceptedV1
        }
        defaults.set(2, forKey: Keys.developerAppearanceDefaultsVersion)
        developerPreviewEnabled = defaults.bool(forKey: Keys.developerPreviewEnabled)
        developerPreviewPreset = DeveloperPreviewPreset(
            rawValue: defaults.string(forKey: Keys.developerPreviewPreset) ?? ""
        ) ?? .normal
        developerPreviewRemainingPercent = Self.storedPreviewPercent(
            defaults,
            key: Keys.developerPreviewRemainingPercent,
            fallback: 72
        )
        developerPreviewRemainingTimePercent = Self.storedPreviewPercent(
            defaults,
            key: Keys.developerPreviewRemainingTimePercent,
            fallback: 55
        )
        L10n.language = language
        refreshLaunchAtLoginStatus()
    }

    var homeURL: URL {
        URL(fileURLWithPath: NSString(string: homePath).expandingTildeInPath, isDirectory: true)
    }

    func refreshLoginStatus() { refreshLaunchAtLoginStatus() }

    func referenceBalance(for currency: String) -> Decimal? {
        let text = (referenceBalances[currency] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 40,
              text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN, amount > 0 else { return nil }
        return amount
    }

    func balanceDisplayStyle(for currency: String) -> MenuBarDisplayStyle {
        guard referenceBalance(for: currency) != nil else { return .percentageOnly }
        return menuBarStyle == .dualBars ? .horizontalBarBesidePercentage : menuBarStyle
    }

    func resetDeveloperOptions() {
        menuBarStyle = .progressAndPercentage
        developerAppearance = .acceptedV1
        developerPreviewEnabled = false
        developerPreviewPreset = .normal
        developerPreviewRemainingPercent = 72
        developerPreviewRemainingTimePercent = 55
    }

    func setPopoverSection(_ section: PopoverContentSection, visible: Bool) {
        var updated = popoverContent
        updated.setSection(section, visible: visible)
        popoverContent = updated
    }

    func setQuotaWindow(_ window: BalanceInfo, visible: Bool) {
        var updated = popoverContent
        updated.setQuotaWindow(window, visible: visible)
        popoverContent = updated
    }

    func movePopoverSection(_ section: PopoverContentSection, by offset: Int) {
        var updated = popoverContent
        updated.moveSection(section, by: offset)
        popoverContent = updated
    }

    func setMenuBarQuotaWindowID(_ id: String?) {
        var updated = popoverContent
        updated.menuBarQuotaWindowID = id
        popoverContent = updated
    }

    func resetPopoverContent() {
        popoverContent = .defaultValue
    }

    var developerPreviewSnapshot: MenuBarPreviewSnapshot {
        if developerPreviewPreset == .custom {
            return .custom(
                remainingPercent: developerPreviewRemainingPercent,
                remainingTimePercent: developerPreviewRemainingTimePercent
            )
        }

        let snapshot = developerPreviewPreset.snapshot
        guard developerPreviewPreset == .longText else { return snapshot }
        return MenuBarPreviewSnapshot(
            remainingPercent: snapshot.remainingPercent,
            remainingTimePercent: snapshot.remainingTimePercent,
            title: L10n.string("developer.preview_long_title"),
            attentionLevel: snapshot.attentionLevel,
            isStale: snapshot.isStale
        )
    }

    func selectDeveloperPreviewPreset(_ preset: DeveloperPreviewPreset) {
        developerPreviewPreset = preset
        guard preset != .custom else { return }

        let snapshot = developerPreviewSnapshot
        if let remainingPercent = snapshot.remainingPercent {
            developerPreviewRemainingPercent = Double(remainingPercent)
        }
        if let remainingTimePercent = snapshot.remainingTimePercent {
            developerPreviewRemainingTimePercent = remainingTimePercent
        }
    }

    func setDeveloperPreviewRemainingPercent(_ value: Double) {
        developerPreviewRemainingPercent = value.clamped(to: 0...100)
        developerPreviewPreset = .custom
    }

    func setDeveloperPreviewRemainingTimePercent(_ value: Double) {
        developerPreviewRemainingTimePercent = value.clamped(to: 0...100)
        developerPreviewPreset = .custom
    }

    func developerConfigurationJSON() -> String? {
        let configuration = DeveloperAppearanceExport(
            menuBarStyle: menuBarStyle,
            appearance: developerAppearance.normalized()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(configuration) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func showSettingsError(_ message: String, destination: SettingsDestination? = nil) {
        settingsDestination = destination
        settingsError = message
    }

    func clearSettingsError() {
        settingsError = nil
        settingsDestination = nil
    }

    func openRelevantSystemSettings() {
        // These URLs open the pane where macOS owns the final permission state.
        let urlString: String
        switch settingsDestination {
        case .notifications:
            let bundleID = Bundle.main.bundleIdentifier ?? "com.huang.DSHMeter"
            urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
        case .loginItems:
            urlString = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        case nil:
            return
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
            // Registration may succeed while macOS still requires user approval.
            if SMAppService.mainApp.status == .requiresApproval {
                showSettingsError(
                    L10n.string("settings.launch_requires_approval"),
                    destination: .loginItems
                )
            } else {
                clearSettingsError()
            }
        } catch {
            refreshLaunchAtLoginStatus()
            showSettingsError(
                L10n.format("settings.launch_error_format", error.localizedDescription),
                destination: .loginItems
            )
        }
    }

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        // Keep the toggle on when registration exists but awaits system approval.
        launchAtLogin = status == .enabled || status == .requiresApproval
    }

    private static func storedPreviewPercent(
        _ defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        let stored = (defaults.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        return stored.clamped(to: 0...100)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

private struct DeveloperAppearanceExport: Codable {
    let menuBarStyle: MenuBarDisplayStyle
    let appearance: MenuBarAppearance
}

enum L10n {
    static var language = AppLanguage.system
    static var locale: Locale { Locale(identifier: code ?? Locale.current.identifier) }
    private static var code: String? {
        guard language != .system else { return nil }
        return language.rawValue
    }
    static func string(_ key: String) -> String {
        let bundle = code.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:)) ?? Bundle.main
        return NSLocalizedString(key, bundle: bundle, value: key, comment: "")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
    static func money(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.currencySymbol = currency == "CNY" ? "¥" : "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = amount != 0 && abs(NSDecimalNumber(decimal: amount).doubleValue) < 0.01 ? 4 : 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
    }
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    static func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    static func menuMoney(_ amount: Decimal, currency: String) -> String {
        let magnitude = abs(NSDecimalNumber(decimal: amount).doubleValue)
        let divisor: Decimal = magnitude >= 1_000_000 ? 1_000_000 : (magnitude >= 1_000 ? 1_000 : 1)
        let suffix = magnitude >= 1_000_000 ? "M" : (magnitude >= 1_000 ? "K" : "")
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = suffix.isEmpty ? 2 : 0
        formatter.maximumFractionDigits = suffix.isEmpty && magnitude < 0.01 && magnitude > 0 ? 4 : 2
        let value = formatter.string(from: NSDecimalNumber(decimal: amount / divisor)) ?? "—"
        return (currency == "CNY" ? "¥" : "$") + value + suffix
    }
}
