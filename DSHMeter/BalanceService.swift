import AppKit
import Combine
import DSHMeterCore
import Foundation

@MainActor
final class BalanceService: ObservableObject {
    @Published private(set) var snapshot: BalanceSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isStale = false
    @Published private(set) var error: DSHMeterError?
    @Published private(set) var source: CredentialSource?
    @Published private(set) var nextRetry: Date?
    private let settings: AppSettings
    private let client = BalanceClient()
    private var activeFingerprint: String?
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var generation = UUID()
    private var schedule = RefreshSchedule()
    private var isPopoverVisible = false
    private var wakeObserver: NSObjectProtocol?

    init(settings: AppSettings) {
        self.settings = settings
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    deinit {
        timer?.invalidate()
        task?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var selectedBalance: BalanceInfo? {
        snapshot?.balanceInfos.first { $0.currency.rawValue == settings.preferredCurrency }
            ?? snapshot?.balanceInfos.first
    }

    var menuBarTitle: String {
        if let balance = selectedBalance { return L10n.money(balance.totalBalance, currency: balance.currency.rawValue) }
        return isRefreshing ? "…" : "—"
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible { refresh() }
        scheduleRefresh()
    }

    func changeHome() {
        generation = UUID()
        task?.cancel()
        task = nil
        timer?.invalidate()
        snapshot = nil
        source = nil
        activeFingerprint = nil
        error = nil
        isStale = false
        isRefreshing = false
        refresh()
        scheduleRefresh()
    }

    func refresh() {
        let now = Date()
        guard task == nil, schedule.mayRefresh(at: now) else { return }
        timer?.invalidate()
        isRefreshing = true
        schedule.started(at: now)
        let home = settings.homeURL
        let currentGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let credential = try await Task.detached(priority: .utility) {
                    try DSHCredentialReader.load(home: home)
                }.value
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                if self.activeFingerprint != credential.fingerprint {
                    self.snapshot = nil
                    self.isStale = false
                    self.activeFingerprint = credential.fingerprint
                }
                self.source = credential.source
                let snapshot = try await self.client.fetch(credential: credential,
                                                          locale: L10n.locale.identifier,
                                                          version: BundleInfo.version)
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                let current = try await Task.detached(priority: .utility) {
                    try DSHCredentialReader.load(home: home)
                }.value
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                guard current.fingerprint == credential.fingerprint else {
                    self.snapshot = nil
                    self.source = current.source
                    self.activeFingerprint = current.fingerprint
                    self.error = nil
                    self.isStale = false
                    self.isRefreshing = false
                    self.task = nil
                    self.schedule.succeeded()
                    self.nextRetry = nil
                    self.scheduleRefresh()
                    return
                }
                self.snapshot = snapshot
                self.error = nil
                self.isStale = false
                self.schedule.succeeded()
                self.nextRetry = nil
            } catch {
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                let failure = error as? DSHMeterError ?? .network
                self.error = failure
                switch failure {
                case .credentialMissing, .credentialUnreadable, .credentialPermissions,
                     .credentialTooLarge, .credentialMalformed, .invalidCredential:
                    self.snapshot = nil
                    self.source = nil
                    self.activeFingerprint = nil
                default: break
                }
                self.isStale = self.snapshot != nil
                self.schedule.failed(rateLimited: failure == .rateLimited, at: Date())
                self.nextRetry = self.schedule.retryAt
            }
            guard self.generation == currentGeneration else { return }
            self.isRefreshing = false
            self.task = nil
            self.scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        guard task == nil else { return }
        let due = schedule.nextRefresh(popoverVisible: isPopoverVisible)
        timer = Timer.scheduledTimer(withTimeInterval: max(0.1, due.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
