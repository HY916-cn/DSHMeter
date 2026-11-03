import AppKit
import DSHMeterCore
import SwiftUI

enum ProjectLinks {
    static let repository = URL(string: "https://github.com/HY916-cn/DSHMeter")!
    static let tutorial = URL(string: "https://github.com/HY916-cn/DSHMeter#首次使用")!
    static let balancePage = URL(string: "https://platform.deepseek.com/usage")!
    static func openDSH() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.deepseek.dsh.desktop.next")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.deepseek.dsh.desktop") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        } else {
            NSWorkspace.shared.open(URL(string: "https://www.deepseek.com/harness/")!)
        }
    }
}

extension DSHMeterError {
    var displayMessage: String {
        let key: String
        switch self {
        case .credentialMissing: key = "error.credential_missing"
        case .credentialUnreadable: key = "error.credential_unreadable"
        case .credentialPermissions: key = "error.credential_permissions"
        case .credentialTooLarge, .credentialMalformed: key = "error.credential_malformed"
        case .invalidCredential: key = "error.credential_malformed"
        case .unauthorized: key = "error.unauthorized"
        case .rateLimited: key = "error.rate_limited"
        case .serverError: key = "error.server"
        case .httpError, .invalidResponse: key = "error.response"
        case .network: key = "error.network"
        case .timedOut: key = "error.timeout"
        case .redirected: key = "error.redirect"
        case .cancelled: key = "error.cancelled"
        }
        return L10n.string(key)
    }
}


extension BalanceInfo: Identifiable {
    public var id: String { currency.rawValue }
    var historyID: String { currency.rawValue }
    var name: String { L10n.string("balance.title") + " · " + currency.rawValue }
}

extension BalanceService {
    var windows: [BalanceInfo] {
        let all = snapshot?.balanceInfos ?? []
        return all.sorted { ($0.currency.rawValue == settingsCurrency ? 0 : 1) < ($1.currency.rawValue == settingsCurrency ? 0 : 1) }
    }
    private var settingsCurrency: String { selectedBalance?.currency.rawValue ?? "CNY" }
    var isLoading: Bool { isRefreshing }
    var isRefreshInFlight: Bool { isRefreshing }
    var lastUpdated: Date? { snapshot?.fetchedAt }
    var accountDescription: String {
        source == .signedInAccount ? L10n.string("account.deepseek") : "DeepSeek API"
    }
    var errorMessage: String? {
        guard let error else { return nil }
        return error.displayMessage + (nextRetry.map { " " + L10n.string("error.retry_at") + " " + L10n.time($0) } ?? "")
    }
    func refreshIfNeeded() { refresh() }
}

enum CodexMeterWindowID {
    static let settings = "app-settings"
    static let about = "about"
}
