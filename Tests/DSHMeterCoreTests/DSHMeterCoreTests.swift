import Foundation
import XCTest
@testable import DSHMeterCore

final class DSHCredentialReaderTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private func write(_ text: String, file: String = ".credentials.yaml", mode: Int = 0o600) throws {
        let url = home.appendingPathComponent(file)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    func testStoredKeyWinsAndFingerprintChangesWithKey() throws {
        try write("version: 1\nrefs:\n  DEEPSEEK_API_KEY: fixture-stored\nrecords:\n  service/id:\n    payload:\n      access: fixture-unrelated\n")
        try write("DEEPSEEK_API_KEY=fixture-dotenv", file: ".env")
        let resolved = try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-environment"])
        XCTAssertEqual(resolved.key, "fixture-stored")
        XCTAssertEqual(resolved.source, .storedFile)
        XCTAssertEqual(resolved.fingerprint.count, 64)
        XCTAssertFalse(String(reflecting: resolved).contains(resolved.key))
        try write("DEEPSEEK_API_KEY: fixture-updated")
        let updated = try DSHCredentialReader.load(home: home, environment: [:])
        XCTAssertNotEqual(resolved.fingerprint, updated.fingerprint)
        XCTAssertEqual(updated.key, "fixture-updated")
    }

    func testMissingStoredKeyFallsBackToEnvironmentThenHomeEnvironment() throws {
        try write("version: 1\nrefs:\n  OTHER_API_KEY: fixture-other\n")
        try write("OTHER_KEY=ignored\nexport DEEPSEEK_API_KEY = 'fixture-dotenv' # comment\n", file: ".env")
        let environment = try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-environment"])
        XCTAssertEqual(environment.key, "fixture-environment")
        XCTAssertEqual(environment.source, .environment)
        let dotenv = try DSHCredentialReader.load(home: home, environment: [:])
        XCTAssertEqual(dotenv.key, "fixture-dotenv")
        XCTAssertEqual(dotenv.source, .homeEnvironment)
    }

    func testMissingFileUsesEnvironmentAndMissingEverythingFails() throws {
        XCTAssertEqual(try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-environment"]).source, .environment)
        XCTAssertThrowsError(try DSHCredentialReader.load(home: home, environment: [:])) {
            XCTAssertEqual($0 as? DSHMeterError, .credentialMissing)
        }
    }

    func testMalformedAndDuplicateYAMLBlockFallbackAndHideSource() throws {
        for yaml in [
            "", "# empty store",
            "version: 1\nrefs: [fixture-sensitive",
            "version: 1\nrefs:\n  DEEPSEEK_API_KEY: fixture-sensitive\n  DEEPSEEK_API_KEY: fixture-other",
            "version: 1\nrefs:\n  DEEPSEEK_API_KEY: fixture-sensitive\n  'DEEPSEEK_API_KEY': fixture-other",
            "version: 2\nrefs: {}",
            "version: 1\nrefs:\n  DEEPSEEK_API_KEY: 123",
            "version: 1\nrefs:\n  DEEPSEEK_API_KEY: ''",
            "version: 1\nrefs: {}\n---\nDEEPSEEK_API_KEY: fixture-sensitive"
        ] {
            try write(yaml)
            XCTAssertThrowsError(try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-fallback"])) {
                XCTAssertEqual($0 as? DSHMeterError, .credentialMalformed)
                XCTAssertFalse(String(reflecting: $0).contains("fixture-sensitive"))
                XCTAssertFalse($0.localizedDescription.contains("fixture-sensitive"))
            }
        }
    }

    func testFilePermissionsSizeAndSymlinksAreChecked() throws {
        try write("DEEPSEEK_API_KEY: fixture-file", mode: 0o644)
        XCTAssertThrowsError(try DSHCredentialReader.load(home: home, environment: [:])) {
            XCTAssertEqual($0 as? DSHMeterError, .credentialPermissions)
        }
        try write(String(repeating: "a", count: 1_048_577))
        XCTAssertThrowsError(try DSHCredentialReader.load(home: home, environment: [:])) {
            XCTAssertEqual($0 as? DSHMeterError, .credentialTooLarge)
        }
        try FileManager.default.removeItem(at: home.appendingPathComponent(".credentials.yaml"))
        try FileManager.default.createSymbolicLink(atPath: home.appendingPathComponent(".credentials.yaml").path, withDestinationPath: "missing-target")
        XCTAssertThrowsError(try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-fallback"])) {
            XCTAssertEqual($0 as? DSHMeterError, .credentialUnreadable)
        }
    }

    func testInvalidEnvironmentCredentialAndDuplicateDotenvFail() throws {
        XCTAssertThrowsError(try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture\r\nInjected: secret"])) {
            XCTAssertEqual($0 as? DSHMeterError, .invalidCredential)
        }
        try write("DEEPSEEK_API_KEY=fixture-one\nDEEPSEEK_API_KEY=fixture-two", file: ".env")
        XCTAssertThrowsError(try DSHCredentialReader.load(home: home, environment: [:])) {
            XCTAssertEqual($0 as? DSHMeterError, .credentialMalformed)
        }
    }
}

private func balanceJSON(total: String = "12.3400", currency: String = "CNY") -> String {
    #"{"is_available":true,"balance_infos":[{"currency":"\#(currency)","total_balance":"\#(total)","granted_balance":"0.0001","topped_up_balance":"12.3399"}]}"#
}

final class BalanceSnapshotTests: XCTestCase {
    func testExactDecimalAndRawAmountRoundTrip() throws {
        let snapshot = try JSONDecoder().decode(BalanceSnapshot.self, from: Data(balanceJSON(total: "-0.0100").utf8))
        XCTAssertEqual(snapshot.balanceInfos[0].totalBalance, Decimal(string: "-0.01"))
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("-0.0100"))
        XCTAssertEqual(try JSONDecoder().decode(BalanceSnapshot.self, from: encoded), snapshot)
    }

    func testMalformedAmountsAndCurrenciesAreRejected() throws {
        for value in ["", " ", "NaN", "Infinity", "1e3", "1.2suffix", "+1", ".5", "1.", "1,23", "--1", "1\\n", "0.1234567890123456789012345678901234567890123456789"] {
            XCTAssertThrowsError(try JSONDecoder().decode(BalanceSnapshot.self, from: Data(balanceJSON(total: value).utf8)), value)
        }
        for currency in ["", "EUR", "cny"] {
            XCTAssertThrowsError(try JSONDecoder().decode(BalanceSnapshot.self, from: Data(balanceJSON(currency: currency).utf8)))
        }
    }

    func testMissingFieldsEmptyListAndDuplicateCurrenciesAreRejected() throws {
        let valid = balanceJSON()
        let missingAmount = valid.replacingOccurrences(of: ",\"granted_balance\":\"0.0001\"", with: "")
        let invalids = [
            #"{"is_available":true,"balance_infos":[]}"#,
            #"{"balance_infos":[]}"#,
            valid.replacingOccurrences(of: "\"12.3400\"", with: "12.34"),
            missingAmount,
            valid.replacingOccurrences(of: "]}", with: "," + String(valid.split(separator: "[")[1].dropLast(2)) + "]}")
        ]
        for json in invalids {
            XCTAssertThrowsError(try JSONDecoder().decode(BalanceSnapshot.self, from: Data(json.utf8)))
        }
    }
}

private final class BalanceURLProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var body = balanceJSON()
        var error: URLError?
    }
    static var reply = Reply()
    static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ value: Reply) { lock.withLock { reply = value; requests = [] } }
    static func captured() -> [URLRequest] { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock { Self.requests.append(request); return Self.reply }
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Location": "https://example.invalid/redirect"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BalanceClientTests: XCTestCase {
    private func client() -> BalanceClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BalanceURLProtocol.self]
        return BalanceClient(configuration: configuration)
    }

    func testOnlyOfficialBalanceGETReceivesBearerKey() async throws {
        BalanceURLProtocol.reset(.init())
        let snapshot = try await client().fetch(key: "fixture-api-key")
        XCTAssertEqual(snapshot.balanceInfos[0].totalBalance, Decimal(string: "12.34"))
        let requests = BalanceURLProtocol.captured()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-api-key")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testHTTPAndNetworkErrorsAreTypedAndSanitized() async {
        for (status, expected) in [(401, DSHMeterError.unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .serverError(500)), (400, .httpError(400)), (302, .redirected), (307, .redirected)] {
            BalanceURLProtocol.reset(.init(status: status, body: "fixture-sensitive-body"))
            do { _ = try await client().fetch(key: "fixture-api-key"); XCTFail("Expected error") }
            catch {
                XCTAssertEqual(error as? DSHMeterError, expected)
                XCTAssertFalse(String(reflecting: error).contains("fixture-sensitive"))
                XCTAssertEqual(BalanceURLProtocol.captured().count, 1)
            }
        }
        for (code, expected) in [(URLError.Code.timedOut, DSHMeterError.timedOut), (.notConnectedToInternet, .network), (.cancelled, .cancelled)] {
            BalanceURLProtocol.reset(.init(error: URLError(code, userInfo: [NSLocalizedDescriptionKey: "fixture-api-key"])))
            do { _ = try await client().fetch(key: "fixture-api-key"); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? DSHMeterError, expected); XCTAssertFalse(String(reflecting: error).contains("fixture-api-key")) }
        }
    }

    func testBadJSONIsSanitizedAndHeaderInjectionNeverSends() async {
        BalanceURLProtocol.reset(.init(body: "{fixture-api-key"))
        do { _ = try await client().fetch(key: "fixture-api-key"); XCTFail("Expected error") }
        catch { XCTAssertEqual(error as? DSHMeterError, .invalidResponse) }
        BalanceURLProtocol.reset(.init())
        do { _ = try await client().fetch(key: "fixture\nInjected: value"); XCTFail("Expected error") }
        catch { XCTAssertEqual(error as? DSHMeterError, .invalidCredential) }
        XCTAssertTrue(BalanceURLProtocol.captured().isEmpty)
    }

    func testRedirectDelegateDeclinesNewRequest() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let origin = URL(string: "https://api.deepseek.com/user/balance")!
        let response = HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let task = session.dataTask(with: origin)
        var redirected = URLRequest(url: URL(string: "https://example.invalid/redirect")!)
        redirected.setValue("Bearer fixture-api-key", forHTTPHeaderField: "Authorization")
        var called = false
        BalanceRedirectBlocker().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { accepted in
            called = true
            XCTAssertNil(accepted)
        }
        XCTAssertTrue(called)
    }
}
