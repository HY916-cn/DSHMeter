import Foundation

package final class BalanceRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    package override init() { super.init() }

    package func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public final class BalanceClient: Sendable {
    private static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!
    private static let accountEndpoint = URL(string: "https://platform.deepseek.com/api/v0/users/get_user_summary")!
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: BalanceRedirectBlocker(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func fetch(key: String) async throws -> BalanceSnapshot {
        try validateCredential(key)
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await fetch(request, account: false)
    }

    public func fetch(credential: ResolvedCredential, locale: String, version: String) async throws -> BalanceSnapshot {
        guard credential.source == .signedInAccount else { return try await fetch(key: credential.key) }
        try validateCredential(credential.key)
        guard !version.isEmpty, version.utf8.count <= 128,
              version.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw DSHMeterError.invalidResponse
        }
        var request = URLRequest(url: Self.accountEndpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(credential.key, forHTTPHeaderField: "x-dsh-auth-token")
        request.setValue("", forHTTPHeaderField: "x-client-bundle-id")
        request.setValue("desktop-mac", forHTTPHeaderField: "x-client-platform")
        request.setValue(version, forHTTPHeaderField: "x-client-version")
        request.setValue(locale.lowercased().hasPrefix("zh") ? "zh_CN" : "en_US", forHTTPHeaderField: "x-client-locale")
        request.setValue(String(TimeZone.current.secondsFromGMT()), forHTTPHeaderField: "x-client-timezone-offset")
        request.setValue("DSHMeter/\(version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await fetch(request, account: true)
    }

    private func fetch(_ request: URLRequest, account: Bool) async throws -> BalanceSnapshot {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.url == request.url else { throw DSHMeterError.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 300..<400: throw DSHMeterError.redirected
            case 401, 403: throw DSHMeterError.unauthorized
            case 429: throw DSHMeterError.rateLimited
            case 500..<600: throw DSHMeterError.serverError(response.statusCode)
            default: throw DSHMeterError.httpError(response.statusCode)
            }
            guard data.count <= 1_048_576 else { throw DSHMeterError.invalidResponse }
            let result: BalanceSnapshot
            do {
                if account {
                    result = try JSONDecoder().decode(AccountBalanceResponse.self, from: data).snapshot()
                } else {
                    result = try JSONDecoder().decode(BalanceSnapshot.self, from: data)
                }
            } catch let error as DSHMeterError { throw error }
            catch { throw DSHMeterError.invalidResponse }
            return try BalanceSnapshot(isAvailable: result.isAvailable, balanceInfos: result.balanceInfos, fetchedAt: Date())
        } catch let error as DSHMeterError { throw error }
        catch is CancellationError { throw DSHMeterError.cancelled }
        catch let error as URLError {
            switch error.code {
            case .timedOut: throw DSHMeterError.timedOut
            case .cancelled: throw DSHMeterError.cancelled
            default: throw DSHMeterError.network
            }
        } catch { throw DSHMeterError.network }
    }
}

private struct AccountBalanceResponse: Decodable {
    private struct Wallet: Decodable {
        let currency: BalanceCurrency
        let balance: String
    }

    private struct Summary: Decodable {
        let normal_wallets: [Wallet]
        let bonus_wallets: [Wallet]
    }

    private enum CodingKeys: String, CodingKey { case code, data }
    private enum DataKeys: String, CodingKey { case biz_code, biz_data }
    private let summary: Summary

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let code = try values.decode(Int.self, forKey: .code)
        if code == 40003 { throw DSHMeterError.unauthorized }
        guard code == 0 else { throw DSHMeterError.invalidResponse }
        let data = try values.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        guard try data.decode(Int.self, forKey: .biz_code) == 0 else { throw DSHMeterError.invalidResponse }
        summary = try data.decode(Summary.self, forKey: .biz_data)
    }

    func snapshot() throws -> BalanceSnapshot {
        let normal = try amounts(summary.normal_wallets)
        let bonus = try amounts(summary.bonus_wallets)
        var balances: [BalanceInfo] = []
        for currency in [BalanceCurrency.CNY, .USD] where normal[currency] != nil || bonus[currency] != nil {
            balances.append(try BalanceInfo(
                currency: currency, toppedUpBalance: normal[currency] ?? 0, grantedBalance: bonus[currency] ?? 0
            ))
        }
        return try BalanceSnapshot(isAvailable: balances.contains { $0.totalBalance > 0 }, balanceInfos: balances)
    }

    private func amounts(_ wallets: [Wallet]) throws -> [BalanceCurrency: Decimal] {
        var result: [BalanceCurrency: Decimal] = [:]
        for wallet in wallets {
            var current = result[wallet.currency] ?? 0
            var amount = try BalanceInfo.accountAmount(wallet.balance)
            var sum = Decimal()
            guard NSDecimalAdd(&sum, &current, &amount, .plain) == .noError, !sum.isNaN else {
                throw DSHMeterError.invalidResponse
            }
            result[wallet.currency] = sum
        }
        return result
    }
}
