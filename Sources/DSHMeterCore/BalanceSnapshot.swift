import Foundation

public enum BalanceCurrency: String, Codable, Sendable {
    case CNY
    case USD
}

public struct BalanceInfo: Codable, Equatable, Sendable {
    public let currency: BalanceCurrency
    public let totalBalance: Decimal
    public let grantedBalance: Decimal
    public let toppedUpBalance: Decimal
    private let totalRaw: String
    private let grantedRaw: String
    private let toppedUpRaw: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            currency = try values.decode(BalanceCurrency.self, forKey: .currency)
            totalRaw = try values.decode(String.self, forKey: .totalBalance)
            grantedRaw = try values.decode(String.self, forKey: .grantedBalance)
            toppedUpRaw = try values.decode(String.self, forKey: .toppedUpBalance)
            totalBalance = try Self.amount(totalRaw)
            grantedBalance = try Self.amount(grantedRaw)
            toppedUpBalance = try Self.amount(toppedUpRaw)
        } catch { throw DSHMeterError.invalidResponse }
    }

    init(currency: BalanceCurrency, toppedUpBalance: Decimal, grantedBalance: Decimal) throws {
        var toppedUp = toppedUpBalance
        var granted = grantedBalance
        var total = Decimal()
        guard NSDecimalAdd(&total, &toppedUp, &granted, .plain) == .noError, !total.isNaN else {
            throw DSHMeterError.invalidResponse
        }
        self.currency = currency
        self.toppedUpBalance = toppedUpBalance
        self.grantedBalance = grantedBalance
        self.totalBalance = total
        self.toppedUpRaw = NSDecimalNumber(decimal: toppedUpBalance).stringValue
        self.grantedRaw = NSDecimalNumber(decimal: grantedBalance).stringValue
        self.totalRaw = NSDecimalNumber(decimal: total).stringValue
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(currency, forKey: .currency)
        try values.encode(totalRaw, forKey: .totalBalance)
        try values.encode(grantedRaw, forKey: .grantedBalance)
        try values.encode(toppedUpRaw, forKey: .toppedUpBalance)
    }

    private static func amount(_ raw: String) throws -> Decimal {
        guard raw.utf8.count <= 256,
              raw.range(of: #"\A-?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN,
              normalized(raw) == normalized(NSDecimalNumber(decimal: decimal).stringValue) else {
            throw DSHMeterError.invalidResponse
        }
        return decimal
    }

    static func accountAmount(_ raw: String) throws -> Decimal {
        guard raw.utf8.count <= 256,
              raw.range(of: #"\A-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z"#,
                        options: .regularExpression) != nil,
              let decimal = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN,
              let expected = normalizedScientific(raw),
              expected == normalizedScientific(NSDecimalNumber(decimal: decimal).stringValue) else {
            throw DSHMeterError.invalidResponse
        }
        return decimal
    }

    private static func normalizedScientific(_ raw: String) -> String? {
        let negative = raw.hasPrefix("-")
        let unsigned = negative ? String(raw.dropFirst()) : raw
        let parts = unsigned.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        guard let exponent = Int(parts.count == 2 ? parts[1] : "0") else { return nil }
        let decimal = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        var digits = String(decimal.joined().drop(while: { $0 == "0" }))
        if digits.isEmpty { return "0" }
        let fractionCount = decimal.count == 2 ? decimal[1].count : 0
        let (initialScale, underflow) = exponent.subtractingReportingOverflow(fractionCount)
        guard !underflow else { return nil }
        var scale = initialScale
        while digits.last == "0" {
            digits.removeLast()
            let (next, overflow) = scale.addingReportingOverflow(1)
            guard !overflow else { return nil }
            scale = next
        }
        return (negative ? "-" : "") + digits + "e" + String(scale)
    }

    // Comparing normalized decimal text catches Foundation's silent precision rounding.
    private static func normalized(_ input: String) -> String {
        let negative = input.hasPrefix("-")
        let unsigned = negative ? String(input.dropFirst()) : input
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(parts[0].drop(while: { $0 == "0" }))
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        while fraction.last == "0" { fraction.removeLast() }
        let zero = integer.isEmpty && fraction.isEmpty
        return (negative && !zero ? "-" : "") + (integer.isEmpty ? "0" : integer) +
            (fraction.isEmpty ? "" : "." + fraction)
    }
}

public struct BalanceSnapshot: Codable, Equatable, Sendable {
    public let isAvailable: Bool
    public let balanceInfos: [BalanceInfo]
    public let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
        case fetchedAt = "fetched_at"
    }

    public init(isAvailable: Bool, balanceInfos: [BalanceInfo], fetchedAt: Date = Date()) throws {
        guard !balanceInfos.isEmpty, Set(balanceInfos.map(\.currency)).count == balanceInfos.count else {
            throw DSHMeterError.invalidResponse
        }
        self.isAvailable = isAvailable
        self.balanceInfos = balanceInfos
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                isAvailable: values.decode(Bool.self, forKey: .isAvailable),
                balanceInfos: values.decode([BalanceInfo].self, forKey: .balanceInfos),
                fetchedAt: values.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
            )
        } catch { throw DSHMeterError.invalidResponse }
    }
}
