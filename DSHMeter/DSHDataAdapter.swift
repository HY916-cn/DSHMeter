import DSHMeterCore
import Foundation

extension DSHMeterError {
    var displayMessage: String {
        let key: String
        switch self {
        case .credentialMissing: key = "error.credential_missing"
        case .credentialUnreadable: key = "error.credential_unreadable"
        case .credentialPermissions: key = "error.credential_permissions"
        case .credentialTooLarge, .credentialMalformed, .invalidCredential:
            key = "error.credential_malformed"
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

extension L10n {
    static func money(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.currencySymbol = currency == "CNY" ? "¥" : "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = amount != 0
            && abs(NSDecimalNumber(decimal: amount).doubleValue) < 0.01 ? 4 : 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
    }

    static func time(_ date: Date) -> String {
        formattedTime(date, includingSeconds: true)
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
