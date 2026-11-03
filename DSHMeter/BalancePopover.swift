import AppKit
import DSHMeterCore
import SwiftUI

struct BalancePopover: View {
    @ObservedObject var service: BalanceService
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DSHMeter").font(.headline)
                    Text("DeepSeek API").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if service.isRefreshing { ProgressView().controlSize(.small) }
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .help(L10n.string("action.refresh"))
                    .accessibilityLabel(L10n.string("action.refresh"))
                    .disabled(service.isRefreshing)
            }

            if service.isStale {
                Label(L10n.string("data.stale"), systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            if let balance = service.selectedBalance, let snapshot = service.snapshot {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.string("balance.title")).font(.subheadline.weight(.semibold))
                        Spacer()
                        Label(L10n.string(snapshot.isAvailable ? "balance.available" : "balance.unavailable"),
                              systemImage: snapshot.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(snapshot.isAvailable ? .green : .orange)
                    }

                    Text(L10n.money(balance.totalBalance, currency: balance.currency.rawValue))
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .textSelection(.enabled)
                        .accessibilityLabel(L10n.string("balance.total") + " "
                                            + L10n.money(balance.totalBalance, currency: balance.currency.rawValue))

                    balanceRow("balance.granted", amount: balance.grantedBalance, currency: balance.currency.rawValue,
                               symbol: "gift", color: .cyan)
                    balanceRow("balance.topped_up", amount: balance.toppedUpBalance, currency: balance.currency.rawValue,
                               symbol: "creditcard", color: .secondary)

                    if snapshot.balanceInfos.count > 1 {
                        Picker(L10n.string("balance.currency"), selection: $settings.preferredCurrency) {
                            ForEach(snapshot.balanceInfos, id: \.currency.rawValue) { item in
                                Text(item.currency.rawValue).tag(item.currency.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.vertical, 2)
            } else if service.error == nil {
                HStack(spacing: 10) {
                    if service.isRefreshing { ProgressView().controlSize(.small) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("loading.balance")).foregroundStyle(.secondary)
                        if let retry = service.nextRetry {
                            Text(L10n.string("error.retry_at") + " " + L10n.time(retry))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            }

            if let error = service.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.string("error.title"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error.displayMessage).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let retry = service.nextRetry {
                        Text(L10n.string("error.retry_at") + " " + L10n.time(retry))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Link(L10n.string("action.tutorial"), destination: ProjectLinks.tutorial)
                        .font(.caption)
                    if service.snapshot == nil {
                        Button(L10n.string("action.open_dsh")) { ProjectLinks.openDSH() }
                            .controlSize(.small)
                    }
                }
            }

            if service.source != nil {
                Label(L10n.string("source.dsh"), systemImage: "lock.shield")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            Button {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                HStack {
                    Label(L10n.string("settings.title"), systemImage: "gearshape")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            HStack {
                Text(service.snapshot.map { L10n.string("status.updated") + " " + L10n.time($0.fetchedAt) }
                     ?? L10n.string("status.local_dsh"))
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button(L10n.string("action.quit")) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { service.setPopoverVisible(true) }
        .onDisappear { service.setPopoverVisible(false) }
    }

    private func balanceRow(_ key: String, amount: Decimal, currency: String, symbol: String, color: Color) -> some View {
        HStack {
            Label(L10n.string(key), systemImage: symbol).foregroundStyle(color)
            Spacer()
            Text(L10n.money(amount, currency: currency)).monospacedDigit()
        }
        .font(.caption)
    }
}

enum ProjectLinks {
    static let repository = URL(string: "https://github.com/HY916-cn/DSHMeter")!
    static let tutorial = URL(string: "https://github.com/HY916-cn/DSHMeter#首次使用")!
    static let balancePage = URL(string: "https://platform.deepseek.com/usage")!
    static func openDSH() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.deepseek.dsh.desktop.next")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "ai.deepseek.dsh.desktop") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        } else {
            NSWorkspace.shared.open(URL(string: "https://www.deepseek.com/harness/")!)
        }
    }
}

extension DSHMeterError {
    var displayMessage: String {
        let key: String
        switch self {
        case .credentialMissing: key = "error.credential_missing"
        case .credentialUnreadable: key = "error.credential_unreadable"
        case .credentialPermissions: key = "error.credential_permissions"
        case .credentialTooLarge, .credentialMalformed: key = "error.credential_malformed"
        case .invalidCredential, .unauthorized: key = "error.unauthorized"
        case .rateLimited: key = "error.rate_limited"
        case .serverError: key = "error.server"
        case .httpError, .invalidResponse: key = "error.response"
        case .network: key = "error.network"
        case .timedOut: key = "error.timeout"
        case .redirected: key = "error.redirect"
        case .cancelled: key = "error.cancelled"
        }
        return L10n.string(key)
    }
}
