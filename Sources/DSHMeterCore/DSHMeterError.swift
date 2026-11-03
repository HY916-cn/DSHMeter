import Foundation

/// Stable error categories; diagnostics never carry credentials or response bodies.
public enum DSHMeterError: Error, Equatable, Sendable {
    case credentialMissing
    case credentialUnreadable
    case credentialPermissions
    case credentialTooLarge
    case credentialMalformed
    case invalidCredential
    case unauthorized
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case invalidResponse
    case network
    case timedOut
    case redirected
    case cancelled
}
