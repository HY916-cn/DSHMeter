import Darwin
import DSHMeterCore
import Foundation

struct CheckFailure: Error {}
func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
    guard condition() else { print("FAIL: \(label)"); throw CheckFailure() }
}
func rejects(_ expected: DSHMeterError, _ body: () throws -> Void) throws {
    do { try body() }
    catch let error as DSHMeterError { try check(error == expected, "typed error"); return }
    throw CheckFailure()
}
let validJSON = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"-0.0100","granted_balance":"0.0001","topped_up_balance":"12.34"}]}"#

final class StubProtocol: URLProtocol {
    static let lock = NSLock()
    static var status = 200
    static var body = validJSON
    static var requests: [URLRequest] = []
    static func configure(status: Int = 200, body: String = validJSON) {
        lock.withLock { Self.status = status; Self.body = body; requests = [] }
    }
    static var captured: [URLRequest] { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.lock.withLock { Self.requests.append(request); return (Self.status, Self.body) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": "https://example.invalid/redirect"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func fixtureChecks() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    func write(_ value: String, file: String = ".credentials.yaml", mode: Int = 0o600) throws {
        let url = home.appendingPathComponent(file)
        try Data(value.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
    try write("version: 1\nrefs:\n  DEEPSEEK_API_KEY: fixture-stored\n")
    let stored = try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-environment"])
    try check(stored.key == "fixture-stored" && stored.source == .storedFile, "stored credential precedence")
    try check(!String(reflecting: stored).contains(stored.key), "credential debug redaction")
    try write("version: 1\nrefs: {}\n")
    let environment = try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-environment"])
    try check(environment.source == .environment, "missing stored key fallback")
    try write("export DEEPSEEK_API_KEY='fixture-dotenv' # comment", file: ".env")
    let dotenv = try DSHCredentialReader.load(home: home, environment: [:])
    try check(dotenv.key == "fixture-dotenv" && dotenv.source == .homeEnvironment, "home environment fallback")
    for yaml in [
        "", "# empty store",
        "version: 1\nrefs: [fixture-sensitive",
        "version: 1\nrefs:\n  DEEPSEEK_API_KEY: fixture-sensitive\n  DEEPSEEK_API_KEY: fixture-other",
        "version: 1\nrefs:\n  DEEPSEEK_API_KEY: fixture-sensitive\n  'DEEPSEEK_API_KEY': fixture-other",
        "version: 1\nrefs:\n  DEEPSEEK_API_KEY: 123",
        "version: 1\nrefs: {}\n---\nDEEPSEEK_API_KEY: fixture-sensitive"
    ] {
        try write(yaml)
        try rejects(.credentialMalformed) {
            _ = try DSHCredentialReader.load(home: home, environment: ["DEEPSEEK_API_KEY": "fixture-fallback"])
        }
    }
    try write("DEEPSEEK_API_KEY: fixture-file", mode: 0o644)
    try rejects(.credentialPermissions) { _ = try DSHCredentialReader.load(home: home, environment: [:]) }
    try write(String(repeating: "a", count: 1_048_577))
    try rejects(.credentialTooLarge) { _ = try DSHCredentialReader.load(home: home, environment: [:]) }
    try write("DEEPSEEK_API_KEY: fixture-flat")
    let flat = try DSHCredentialReader.load(home: home, environment: [:])
    try check(flat.key == "fixture-flat", "legacy flat store")
    let snapshot = try JSONDecoder().decode(BalanceSnapshot.self, from: Data(validJSON.utf8))
    try check(snapshot.balanceInfos[0].totalBalance == Decimal(string: "-0.01"), "exact signed decimal")
    let roundtrip = try JSONEncoder().encode(snapshot)
    try check(String(decoding: roundtrip, as: UTF8.self).contains("-0.0100"), "raw decimal precision")
    for amount in ["NaN", "Infinity", "1e3", "1.2suffix", "1.", ".5", "0.1234567890123456789012345678901234567890123456789"] {
        let json = validJSON.replacingOccurrences(of: "-0.0100", with: amount)
        try rejects(.invalidResponse) { _ = try JSONDecoder().decode(BalanceSnapshot.self, from: Data(json.utf8)) }
    }
    for json in [
        #"{"is_available":true,"balance_infos":[]}"#,
        validJSON.replacingOccurrences(of: "CNY", with: "EUR"),
        validJSON.replacingOccurrences(of: ",\"granted_balance\":\"0.0001\"", with: ""),
        validJSON.replacingOccurrences(of: "]}", with: "," + String(validJSON.split(separator: "[")[1].dropLast(2)) + "]}")
    ] {
        try rejects(.invalidResponse) { _ = try JSONDecoder().decode(BalanceSnapshot.self, from: Data(json.utf8)) }
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    let client = BalanceClient(configuration: configuration)
    StubProtocol.configure()
    _ = try await client.fetch(key: "fixture-api-key")
    let requests = StubProtocol.captured
    try check(requests.count == 1, "single request")
    try check(requests[0].url?.absoluteString == "https://api.deepseek.com/user/balance", "official endpoint")
    try check(requests[0].httpMethod == "GET" && requests[0].httpBody == nil, "balance GET")
    try check(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-api-key", "bearer authorization")
    for (status, expected) in [(401, DSHMeterError.unauthorized), (429, .rateLimited), (500, .serverError(500)), (302, .redirected), (307, .redirected)] {
        StubProtocol.configure(status: status, body: "fixture-sensitive-response")
        do { _ = try await client.fetch(key: "fixture-api-key"); throw CheckFailure() }
        catch let error as DSHMeterError {
            try check(error == expected, "HTTP status mapping")
            try check(!String(reflecting: error).contains("fixture-sensitive"), "response redaction")
        }
        try check(StubProtocol.captured.count == 1, "no follow-up request")
    }
    StubProtocol.configure(body: "{fixture-sensitive-response")
    do { _ = try await client.fetch(key: "fixture-api-key"); throw CheckFailure() }
    catch let error as DSHMeterError { try check(error == .invalidResponse, "malformed JSON") }
    let redirectSession = URLSession(configuration: .ephemeral)
    defer { redirectSession.invalidateAndCancel() }
    let origin = URL(string: "https://api.deepseek.com/user/balance")!
    let task = redirectSession.dataTask(with: origin)
    let redirectResponse = HTTPURLResponse(url: origin, statusCode: 307, httpVersion: nil, headerFields: nil)!
    var proposed = URLRequest(url: URL(string: "https://example.invalid/redirect")!)
    proposed.setValue("Bearer fixture-api-key", forHTTPHeaderField: "Authorization")
    var declined = false
    BalanceRedirectBlocker().urlSession(redirectSession, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: proposed) {
        declined = $0 == nil
    }
    try check(declined, "cross-domain redirect delegate rejection")
    print("PASS: credential, decimal, and HTTP fixture checks")
}

do {
    if CommandLine.arguments.contains("--live") {
        let environment = ProcessInfo.processInfo.environment
        let path = environment["DSH_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh").path
        let credential = try DSHCredentialReader.load(home: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath), environment: environment)
        let snapshot = try await BalanceClient().fetch(key: credential.key)
        print("PASS: official balance query; currencies=\(snapshot.balanceInfos.count)")
    } else {
        try await fixtureChecks()
    }
} catch let error as DSHMeterError {
    print("FAIL: \(String(describing: error))")
    exit(1)
} catch {
    print("FAIL: core checks")
    exit(1)
}
