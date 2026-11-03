import Combine
import CryptoKit
import DSHMeterCore
import Foundation

/// Adapts DSH balances to the source application's observable UI contract.
@MainActor
final class CodexUsageService: ObservableObject {
    @Published private(set) var windows: [CodexUsageWindow] = []
    @Published private(set) var planType: String?
    @Published private(set) var isLoading = true
    @Published private(set) var isRefreshInFlight = false
    @Published private(set) var isStale = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var rateLimitResetCredits: CodexRateLimitResetCreditsSummary?
    @Published private(set) var historyAccountKey: String?

    let balanceService: BalanceService
    let pushNotificationService: PushNotificationService
    private let settings: AppSettings
    private let history: UsageHistoryModel
    private let notificationManager: NotificationManager
    private var observations = Set<AnyCancellable>()
    private var hasStarted = false
    private var activeHomePath: String
    private var lastRecordedAt: Date?
    private var lastRecordedWindows: [CodexUsageWindow] = []

    init(
        settings: AppSettings,
        history: UsageHistoryModel,
        notificationManager: NotificationManager = NotificationManager(),
        pushNotificationService: PushNotificationService? = nil
    ) {
        self.settings = settings
        self.history = history
        self.notificationManager = notificationManager
        self.pushNotificationService = pushNotificationService ?? PushNotificationService(settings: settings)
        activeHomePath = settings.homeURL.standardizedFileURL.path
        balanceService = BalanceService(settings: settings)

        balanceService.objectWillChange.sink { [weak self] _ in
            // Published values become readable after the current mutation completes.
            DispatchQueue.main.async { self?.synchronize() }
        }.store(in: &observations)
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.synchronize() }
        }.store(in: &observations)
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    var snapshot: BalanceSnapshot? { balanceService.snapshot }
    var source: CredentialSource? { balanceService.source }
    var nextRetry: Date? { balanceService.nextRetry }

    var mostConstrainedWindow: CodexUsageWindow? {
        windows.filter { $0.balancePercent != nil }.min {
            $0.remainingPercent < $1.remainingPercent
        } ?? windows.first
    }

    var mostConstrainedRemainingPercent: Int? {
        guard let window = mostConstrainedWindow, window.balancePercent != nil else { return nil }
        return window.remainingPercent
    }

    var menuBarTitle: String { balanceService.menuBarTitle }

    var accountDescription: String {
        source == .signedInAccount ? L10n.string("account.deepseek") : "DeepSeek API"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        balanceService.refresh()
        synchronize()
    }

    func refresh() { balanceService.refresh() }

    func refreshIfNeeded(maxAge: TimeInterval = 10) {
        guard lastUpdated.map({ Date().timeIntervalSince($0) >= maxAge }) ?? true else { return }
        refresh()
    }

    func setPopoverVisible(_ visible: Bool) { balanceService.setPopoverVisible(visible) }

    func changeHome() {
        activeHomePath = settings.homeURL.standardizedFileURL.path
        balanceService.changeHome()
        synchronize()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled else {
            settings.notificationsEnabled = false
            if settings.settingsDestination == .notifications { settings.clearSettingsError() }
            return
        }
        notificationManager.requestAuthorization { [weak self] granted, error in
            guard let self else { return }
            self.settings.notificationsEnabled = granted
            if granted {
                self.settings.clearSettingsError()
                self.notificationManager.evaluate(
                    windows: self.referencedWindows,
                    threshold: self.settings.notificationThreshold
                )
            } else {
                self.settings.showSettingsError(
                    error ?? L10n.string("settings.notification_denied"),
                    destination: .notifications
                )
            }
        }
    }

    func sendTestBarkPush(completion: ((Bool, String?) -> Void)? = nil) {
        pushNotificationService.sendTestBark(completion: completion)
    }

    func sendTestGotifyPush(completion: ((Bool, String?) -> Void)? = nil) {
        pushNotificationService.sendTestGotify(completion: completion)
    }

    private var referencedWindows: [CodexUsageWindow] {
        windows.filter { $0.balancePercent != nil }
    }

    private func synchronize() {
        guard activeHomePath == settings.homeURL.standardizedFileURL.path else {
            changeHome()
            return
        }
        synchronizeIdentity()
        let balances = snapshot?.balanceInfos ?? []
        let parsed = balances.sorted {
            ($0.currency.rawValue == settings.preferredCurrency ? 0 : 1)
                < ($1.currency.rawValue == settings.preferredCurrency ? 0 : 1)
        }.map { balance -> CodexUsageWindow in
            let reference = settings.referenceBalance(for: balance.currency.rawValue)
            // Bound the floating-point ratio before converting it to an integer.
            let remaining = reference.map {
                NSDecimalNumber(decimal: balance.totalBalance).doubleValue
                    / NSDecimalNumber(decimal: $0).doubleValue * 100
            }.map { min(100, max(0, $0)) }
            return CodexUsageWindow(
                id: "balance-\(balance.currency.rawValue)",
                name: L10n.string("balance.title") + " · " + balance.currency.rawValue,
                usedPercent: remaining.map { 100 - Int($0.rounded()) } ?? 0,
                windowDurationMins: nil,
                resetsAt: nil,
                balance: balance,
                balanceReference: reference,
                balanceAvailable: snapshot?.isAvailable
            )
        }
        if windows != parsed { windows = parsed }
        planType = source == .signedInAccount ? "DSH" : (source == nil ? nil : "API")
        isLoading = balanceService.isRefreshing && windows.isEmpty
        isRefreshInFlight = balanceService.isRefreshing
        isStale = balanceService.isStale
        lastUpdated = snapshot?.fetchedAt
        errorMessage = balanceService.error.map { failure in
            failure.displayMessage + (nextRetry.map {
                " " + L10n.string("error.retry_at") + " " + L10n.time($0)
            } ?? "")
        }

        guard !isStale, balanceService.error == nil,
              let date = snapshot?.fetchedAt,
              let historyAccountKey else { return }
        let referenced = referencedWindows
        guard !referenced.isEmpty else { return }
        let changed = referenced.map { ($0.historyID, $0.remainingPercent, $0.name) }
        let previous = lastRecordedWindows.map { ($0.historyID, $0.remainingPercent, $0.name) }
        let sameWindows = changed.elementsEqual(previous) {
            $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2
        }
        guard lastRecordedAt != date || !sameWindows else { return }
        lastRecordedAt = date
        lastRecordedWindows = referenced
        history.recordQuota(
            windows: referenced,
            at: date,
            isStale: false,
            source: .refresh,
            retention: settings.historyRetention,
            accountKey: historyAccountKey
        )
        if settings.notificationsEnabled {
            notificationManager.evaluate(windows: referenced, threshold: settings.notificationThreshold)
        }
        pushNotificationService.evaluate(windows: referenced)
    }

    private func synchronizeIdentity() {
        let key = balanceService.credentialFingerprint.map { fingerprint in
            let material = [settings.historyIdentitySalt, activeHomePath, fingerprint]
                .joined(separator: "\u{0}")
            let digest = SHA256.hash(data: Data(material.utf8))
                .map { String(format: "%02x", $0) }.joined()
            return "dsh:\(digest)"
        }
        guard historyAccountKey != key else { return }
        historyAccountKey = key
        lastRecordedAt = nil
        lastRecordedWindows = []
        notificationManager.resetEvaluationState()
        pushNotificationService.resetEvaluationState()
        if let key {
            history.activateAccount(key, resetExisting: false, claimLegacyHistory: false)
        } else {
            history.deactivateAccount()
        }
    }
}
