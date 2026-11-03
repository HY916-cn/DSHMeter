import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zhHans = "zh-Hans", zhHant = "zh-Hant"
    var id: String { rawValue }
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

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconAndBalance, balanceOnly, iconOnly
    case horizontalBarBesideBalance, compactBarBelowBalance, dualBars
    var id: String { rawValue }
}

enum BundleInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2" }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var homePath: String { didSet { defaults.set(homePath, forKey: "dsh.home") } }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language"); L10n.language = language }
    }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menu.style") } }
    @Published var preferredCurrency: String { didSet { defaults.set(preferredCurrency, forKey: "balance.currency") } }
    @Published var launchAtLogin = false
    @Published var settingsError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        homePath = defaults.string(forKey: "dsh.home") ?? ProcessInfo.processInfo.environment["DSH_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh").path
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "system") ?? .system
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menu.style") ?? "iconAndBalance") ?? .iconAndBalance
        preferredCurrency = defaults.string(forKey: "balance.currency") ?? "CNY"
        L10n.language = language
        refreshLoginStatus()
    }

    var homeURL: URL {
        URL(fileURLWithPath: NSString(string: homePath).expandingTildeInPath, isDirectory: true)
    }

    func refreshLoginStatus() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { settingsError = L10n.string("settings.login_error") }
        refreshLoginStatus()
    }
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
}
