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
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.url == Self.endpoint else { throw DSHMeterError.invalidResponse }
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
            do { result = try JSONDecoder().decode(BalanceSnapshot.self, from: data) }
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
