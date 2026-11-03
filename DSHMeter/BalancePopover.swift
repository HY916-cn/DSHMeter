import AppKit
import DSHMeterCore
import SwiftUI

private struct ScrollOnlyPopoverIndicators: ViewModifier {
    @State private var hasScrolled = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .scrollIndicators(hasScrolled ? .automatic : .hidden)
                .onScrollPhaseChange { _, phase in
                    // Once scrolling begins, let AppKit own its normal fade-out.
                    if phase == .interacting || phase == .decelerating {
                        hasScrolled = true
                    }
                }
                .onAppear { hasScrolled = false }
                .onDisappear { hasScrolled = false }
        } else {
            content
        }
    }
}

struct BalancePopover: View {
    @ObservedObject var service: BalanceService
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var maximumPopoverHeight = PopoverLayoutMetrics.initialMaximumHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header.layoutPriority(1)
            ScrollView {
                scrollableContent.padding(.trailing, 12)
            }
            .modifier(ScrollOnlyPopoverIndicators())
            .clipped()
            .padding(.trailing, -12)
            bottomControls.layoutPriority(1)
        }
        .padding(16)
        .frame(width: 380)
        .frame(maxHeight: maximumPopoverHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            PopoverScreenHeightReader { visibleHeight in
                let height = PopoverLayoutMetrics.maximumHeight(forScreenVisibleHeight: visibleHeight)
                guard abs(maximumPopoverHeight - height) > 0.5 else { return }
                maximumPopoverHeight = height
            }
        }
        .onAppear { settings.refreshLoginStatus(); service.setPopoverVisible(true) }
        .onDisappear { service.setPopoverVisible(false) }
    }

    private var header: some View {
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
    }

    private var scrollableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if service.isStale {
                Label(L10n.string("data.stale"), systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            if let error = service.error { errorView(error) }
            if let balance = service.selectedBalance, let snapshot = service.snapshot {
                BalanceWindowRow(balance: balance, isAvailable: snapshot.isAvailable)
                if snapshot.balanceInfos.count > 1 {
                    Picker(L10n.string("balance.currency"), selection: $settings.preferredCurrency) {
                        ForEach(snapshot.balanceInfos, id: \.currency.rawValue) { item in
                            Text(item.currency.rawValue).tag(item.currency.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorView(_ error: DSHMeterError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if service.snapshot == nil {
                Label(L10n.string("error.title"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.displayMessage).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(error.displayMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry = service.nextRetry {
                Text(L10n.string("error.retry_at") + " " + L10n.time(retry))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Link(destination: ProjectLinks.tutorial) {
                Label(L10n.string("action.tutorial"), systemImage: "book")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if service.snapshot == nil {
                Button(L10n.string("action.open_dsh")) { ProjectLinks.openDSH() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Button {
                openWindow(id: "settings")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape")
                    Text(L10n.string("settings.title"))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("settings.title"))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BalanceWindowRow: View {
    let balance: BalanceInfo
    let isAvailable: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.string("balance.title")).font(.subheadline.weight(.semibold))
                Spacer()
                Label(L10n.string(isAvailable ? "balance.available" : "balance.unavailable"),
                      systemImage: isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isAvailable ? .green : .orange)
            }
            HStack {
                Label(L10n.string("balance.total"), systemImage: "battery.75percent")
                Spacer()
                Text(L10n.money(balance.totalBalance, currency: balance.currency.rawValue)).monospacedDigit()
            }
            .font(.caption)
            BalanceMetricBar(label: L10n.string("balance.topped_up"),
                             amount: balance.toppedUpBalance, currency: balance.currency.rawValue,
                             fraction: balance.toppedUpPercent,
                             tint: colorScheme == .dark ? .white : .black, symbol: "creditcard")
            BalanceMetricBar(label: L10n.string("balance.granted"),
                             amount: balance.grantedBalance, currency: balance.currency.rawValue,
                             fraction: balance.grantedPercent,
                             tint: Color(red: 0.30, green: 0.72, blue: 1), symbol: "gift")
            HStack {
                Label(L10n.string("balance.composition"), systemImage: "chart.pie")
                Spacer()
                Text(balance.currency.rawValue)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct BalanceMetricBar: View {
    let label: String
    let amount: Decimal
    let currency: String
    let fraction: Double?
    let tint: Color
    let symbol: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Label(label, systemImage: symbol)
                Spacer()
                Text(L10n.money(amount, currency: currency)).monospacedDigit()
            }
            .font(.caption)
            ProgressView(value: fraction ?? 0, total: 100)
                .tint(tint)
                .id(colorScheme)
                .opacity(fraction == nil ? 0.25 : 1)
        }
        .help(L10n.string("balance.composition_help"))
        .accessibilityElement(children: .combine)
    }
}

extension BalanceInfo {
    var toppedUpPercent: Double? { percent(toppedUpBalance) }
    var grantedPercent: Double? { percent(grantedBalance) }
    private func percent(_ amount: Decimal) -> Double? {
        guard totalBalance > 0, amount >= 0, amount <= totalBalance else { return nil }
        return NSDecimalNumber(decimal: amount / totalBalance * 100).doubleValue
    }
}

private enum PopoverLayoutMetrics {
    private static let fallbackScreenHeight: CGFloat = 720
    private static let screenEdgeClearance: CGFloat = 16

    static var initialMaximumHeight: CGFloat {
        maximumHeight(forScreenVisibleHeight: NSScreen.main?.visibleFrame.height)
    }

    static func maximumHeight(forScreenVisibleHeight visibleHeight: CGFloat?) -> CGFloat {
        max(1, (visibleHeight ?? fallbackScreenHeight) - screenEdgeClearance)
    }
}

/// Reports the visible height of the display that actually contains the menu
/// bar popover, including updates after display or scaling changes.
private struct PopoverScreenHeightReader: NSViewRepresentable {
    let onVisibleHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenTrackingView {
        ScreenTrackingView(onVisibleHeightChange: onVisibleHeightChange)
    }

    func updateNSView(_ nsView: ScreenTrackingView, context: Context) {
        nsView.onVisibleHeightChange = onVisibleHeightChange
        nsView.publishVisibleHeight()
    }

    final class ScreenTrackingView: NSView {
        var onVisibleHeightChange: (CGFloat) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onVisibleHeightChange: @escaping (CGFloat) -> Void) {
            self.onVisibleHeightChange = onVisibleHeightChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            removeObservers()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installObservers()
            publishVisibleHeight()
        }

        func publishVisibleHeight() {
            guard let visibleHeight = window?.screen?.visibleFrame.height else { return }
            let callback = onVisibleHeightChange
            DispatchQueue.main.async {
                callback(visibleHeight)
            }
        }

        private func installObservers() {
            removeObservers()

            if let window {
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.publishVisibleHeight()
                })
            }

            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.publishVisibleHeight()
            })
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
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
