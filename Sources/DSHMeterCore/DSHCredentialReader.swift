import CryptoKit
import Darwin
import Foundation
import Yams

public enum CredentialSource: String, Sendable {
    case signedInAccount
    case storedFile
    case environment
    case homeEnvironment
}

public struct ResolvedCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let key: String
    public let source: CredentialSource
    public let fingerprint: String

    fileprivate init(key: String, source: CredentialSource) throws {
        try validateCredential(key)
        self.key = key
        self.source = source
        self.fingerprint = SHA256.hash(data: Data("\(source.rawValue)\u{0}\(key)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { "ResolvedCredential(source: \(source.rawValue))" }
    public var debugDescription: String { description }
}

func validateCredential(_ key: String) throws {
    guard !key.isEmpty, key.utf8.count <= 8192,
          key.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
        throw DSHMeterError.invalidCredential
    }
}

public enum DSHCredentialReader {
    public static func load(
        home: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ResolvedCredential {
        if let text = try readPrivateFile(home.appendingPathComponent(".credentials.yaml")),
           let credential = try storedCredential(text) {
            return credential
        }
        if let key = environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return try ResolvedCredential(key: key, source: .environment)
        }
        if let text = try readPrivateFile(home.appendingPathComponent(".env")),
           let key = try environmentKey(text) {
            return try ResolvedCredential(key: key, source: .homeEnvironment)
        }
        throw DSHMeterError.credentialMissing
    }

    private static func readPrivateFile(_ url: URL) throws -> String? {
        let descriptor = url.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw DSHMeterError.credentialUnreadable
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG else { throw DSHMeterError.credentialUnreadable }
        guard metadata.st_uid == getuid(), metadata.st_mode & 0o7777 == 0o600 else {
            throw DSHMeterError.credentialPermissions
        }
        let limit = 1_048_576
        guard metadata.st_size <= limit else { throw DSHMeterError.credentialTooLarge }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw DSHMeterError.credentialUnreadable
            }
            if count == 0 { break }
            guard data.count + count <= limit else { throw DSHMeterError.credentialTooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard let text = String(data: data, encoding: .utf8) else { throw DSHMeterError.credentialMalformed }
        return text
    }

    private static func storedCredential(_ text: String) throws -> ResolvedCredential? {
        do {
            // Yams 6.1 rejects duplicate mapping keys. Explicit UTF-8 avoids parser environment logging.
            guard let root = try compose(yaml: text, .default, .default, .utf8),
                  case .mapping = root else { throw DSHMeterError.credentialMalformed }
            try validateMappingKeys(root)
            if let version = root["version"] {
                guard version.int == 1 else { throw DSHMeterError.credentialMalformed }
                if let records = root["records"] {
                    try validateMappingKeys(records)
                    if let record = records["deepseek-account-platform/default"] {
                        try validateMappingKeys(record)
                        guard record["kind"]?.tag == Tag(.str), record["kind"]?.string == "grant",
                              let payload = record["payload"] else {
                            throw DSHMeterError.credentialMalformed
                        }
                        try validateMappingKeys(payload)
                        guard payload["version"]?.tag == Tag(.int), payload["version"]?.int == 1,
                              payload["issuer"]?.tag == Tag(.str),
                              payload["issuer"]?.string == "https://platform.deepseek.com",
                              let token = try stringKey(payload["token"]) else {
                            throw DSHMeterError.credentialMalformed
                        }
                        return try ResolvedCredential(key: token, source: .signedInAccount)
                    }
                }
                guard let refs = root["refs"] else { return nil }
                guard case .mapping = refs else { throw DSHMeterError.credentialMalformed }
                try validateMappingKeys(refs)
                guard let key = try stringKey(refs["DEEPSEEK_API_KEY"]) else { return nil }
                return try ResolvedCredential(key: key, source: .storedFile)
            }
            // The pre-release store used a flat mapping of reference names.
            guard root["refs"] == nil, root["records"] == nil else {
                throw DSHMeterError.credentialMalformed
            }
            guard let key = try stringKey(root["DEEPSEEK_API_KEY"]) else { return nil }
            return try ResolvedCredential(key: key, source: .storedFile)
        } catch let error as DSHMeterError { throw error }
        catch { throw DSHMeterError.credentialMalformed }
    }

    private static func validateMappingKeys(_ node: Node) throws {
        guard let mapping = node.mapping,
              mapping.allSatisfy({ $0.key.tag == Tag(.str) && $0.key.string?.isEmpty == false }) else {
            throw DSHMeterError.credentialMalformed
        }
    }

    private static func stringKey(_ node: Node?) throws -> String? {
        guard let node else { return nil }
        guard node.tag == Tag(.str), let key = node.string, !key.isEmpty else {
            throw DSHMeterError.credentialMalformed
        }
        return key
    }

    private static func environmentKey(_ text: String) throws -> String? {
        var result: String?
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let equals = line.firstIndex(of: "="),
                  line[..<equals].trimmingCharacters(in: .whitespaces) == "DEEPSEEK_API_KEY" else { continue }
            guard result == nil else { throw DSHMeterError.credentialMalformed }
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.first == "\"" || value.first == "'" {
                let quote = value.removeFirst()
                guard let end = value.firstIndex(of: quote),
                      value[value.index(after: end)...].trimmingCharacters(in: .whitespaces).isEmpty ||
                      value[value.index(after: end)...].trimmingCharacters(in: .whitespaces).hasPrefix("#") else {
                    throw DSHMeterError.credentialMalformed
                }
                value = String(value[..<end])
            } else if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            guard !value.isEmpty else { throw DSHMeterError.credentialMalformed }
            result = value
        }
        return result
    }
}
