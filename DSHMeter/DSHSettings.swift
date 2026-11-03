import Foundation

extension AppSettings {
    var homeURL: URL {
        URL(fileURLWithPath: NSString(string: homePath).expandingTildeInPath, isDirectory: true)
    }

    func referenceBalance(for currency: String) -> Decimal? {
        let text = (referenceBalances[currency] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 40,
              text.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN, amount > 0 else { return nil }
        return amount
    }
}

enum BundleInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.6"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "7"
    }
}
