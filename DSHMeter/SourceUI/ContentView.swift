import AppKit
import SwiftUI
import DSHMeterCore

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

struct ContentView: View {
    @ObservedObject var service: BalanceService
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var maximumPopoverHeight = PopoverLayoutMetrics.initialMaximumHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .layoutPriority(1)

            ScrollView {
                scrollableContent
                    .padding(.trailing, 12)
            }
            .modifier(ScrollOnlyPopoverIndicators())
            .clipped()
            .padding(.trailing, -12)

            bottomControls
                .layoutPriority(1)
        }
        .padding(16)
        .frame(width: 380)
        .frame(maxHeight: maximumPopoverHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            PopoverScreenHeightReader { visibleHeight in
                let updatedHeight = PopoverLayoutMetrics.maximumHeight(
                    forScreenVisibleHeight: visibleHeight
                )
                guard abs(maximumPopoverHeight - updatedHeight) > 0.5 else { return }
                maximumPopoverHeight = updatedHeight
            }
        }
        .onAppear {
            service.setPopoverVisible(true)
            settings.refreshLaunchAtLoginStatus()
            service.refreshIfNeeded()
        }
        .onDisappear {
            service.setPopoverVisible(false)
        }
        .alert(
            L10n.string("settings.error_title"),
            isPresented: Binding(
                get: { settings.settingsError != nil },
                set: { if !$0 { settings.clearSettingsError() } }
            )
        ) {
            Button(L10n.string("action.ok")) {
                settings.clearSettingsError()
            }

            if settings.settingsDestination != nil {
                Button(L10n.string("action.open_system_settings")) {
                    settings.openRelevantSystemSettings()
                    settings.clearSettingsError()
                }
            }
        } message: {
            Text(settings.settingsError ?? "")
        }
    }

    private var scrollableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if settings.developerPreviewEnabled {
                previewModeBanner
            }

            if service.isStale {
                staleBanner
            }

            Divider()

            if service.isLoading && service.windows.isEmpty {
                loadingView
            } else if let errorMessage = service.errorMessage,
                      service.windows.isEmpty {
                errorView(errorMessage)
            } else {
                if let errorMessage = service.errorMessage {
                    inlineErrorView(errorMessage)
                }

                configurableContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            SettingsSection(service: service, settings: settings)
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("app.title"))
                    .font(.headline)

                Text(service.accountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if service.isRefreshInFlight {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                service.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(L10n.string("action.refresh"))
            .disabled(service.isRefreshInFlight)
        }
    }

    private var staleBanner: some View {
        Label(L10n.string("data.stale"), systemImage: "clock.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var previewModeBanner: some View {
        HStack(spacing: 8) {
            Label(
                L10n.string("developer.preview_mode_active"),
                systemImage: "eye.trianglebadge.exclamationmark"
            )
            .font(.caption)
            .foregroundStyle(.orange)

            Spacer()

            Button(L10n.string("developer.return_to_live")) {
                settings.developerPreviewEnabled = false
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.string("loading.usage"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("error.cannot_read"), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            setupReadmeLink
            Button(L10n.string("action.open_dsh")) { ProjectLinks.openDSH() }
            Button(L10n.string("action.retry")) {
                service.refresh()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
    }

    private func inlineErrorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            setupReadmeLink
            Button(L10n.string("action.open_dsh")) { ProjectLinks.openDSH() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupReadmeLink: some View {
        Link(destination: ProjectLinks.tutorial) {
            Label(L10n.string("action.open_setup_readme"), systemImage: "book")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var visibleQuotaWindows: [BalanceInfo] {
        settings.popoverContent.visibleQuotaWindows(from: service.windows)
    }

    private var displayedSections: [PopoverContentSection] {
        settings.popoverContent.sectionOrder.filter { section in
            guard settings.popoverContent.isSectionVisible(section) else { return false }

            switch section {
            case .quotaWindows:
                return !visibleQuotaWindows.isEmpty
            }
        }
    }

    private var configurableContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(displayedSections) { section in
                if section != displayedSections.first {
                    Divider()
                }

                popoverSection(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func popoverSection(_ section: PopoverContentSection) -> some View {
        switch section {
        case .quotaWindows:
            usageView

        }
    }

    private var usageView: some View {
        // Keep the source component's local presentation timeline.
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            VStack(spacing: 16) {
                ForEach(visibleQuotaWindows) { window in
                    UsageWindowRow(
                        window: window,
                        now: context.date,
                        appearance: settings.developerAppearance,
                        reference: settings.referenceBalance(for: window.currency.rawValue)
                    )

                    if window.id != visibleQuotaWindows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = service.lastUpdated {
                Text(L10n.format(
                    "status.updated_at_format",
                    L10n.formattedDateTime(lastUpdated)
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            } else {
                Text(L10n.string("status.local_server"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(L10n.string("action.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
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

private struct SettingsSection: View {
    @ObservedObject var service: BalanceService
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: CodexMeterWindowID.settings)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "gearshape")
                Text(L10n.string("settings.title"))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("settings.title"))
    }
}

/// Binds monetary balances to the source app's compact metric rows.
private struct UsageWindowRow: View {
    let window: BalanceInfo
    let now: Date
    let appearance: MenuBarAppearance
    let reference: Decimal?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                paceLabel
            }

            MetricBar(
                label: L10n.string("balance.total"),
                value: remainingPercent,
                tint: appearance.normalColor.swiftUIColor(for: colorScheme),
                symbol: "battery.75percent",
                valueText: L10n.money(window.totalBalance, currency: window.currency.rawValue),
                showsProgress: reference != nil,
                emphasized: true
            )

            MetricBar(
                label: L10n.string("balance.topped_up"),
                value: nil,
                tint: appearance.normalColor.swiftUIColor(for: colorScheme),
                symbol: "creditcard",
                valueText: L10n.money(window.toppedUpBalance, currency: window.currency.rawValue),
                showsProgress: false
            )

            MetricBar(
                label: L10n.string("balance.granted"),
                value: nil,
                tint: appearance.timeColor.swiftUIColor(for: colorScheme),
                symbol: "gift",
                valueText: L10n.money(window.grantedBalance, currency: window.currency.rawValue),
                showsProgress: false
            )

            HStack {
                if let reference {
                    Label(L10n.string("balance.reference") + " " + L10n.money(reference, currency: window.currency.rawValue), systemImage: "gauge.with.dots.needle.50percent")
                } else {
                    Label(L10n.string("balance.amount_help"), systemImage: "banknote")
                }
                Spacer()
                Text(window.currency.rawValue)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var remainingPercent: Double? {
        guard let reference, reference > 0 else { return nil }
        return max(0, min(100, NSDecimalNumber(decimal: window.totalBalance / reference * 100).doubleValue))
    }

    private var paceLabel: some View {
        Label(L10n.string(window.totalBalance > 0 ? "balance.available" : "balance.unavailable"),
              systemImage: window.totalBalance > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(window.totalBalance > 0 ? .green : .orange)
    }
}

private struct MetricBar: View {
    let label: String
    let value: Double?
    let tint: Color
    let symbol: String
    var valueText: String? = nil
    var showsProgress = true
    var emphasized = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Label(label, systemImage: symbol)
                Spacer()
                Text(valueText ?? value.map { "\(Int($0.rounded()))%" } ?? "—")
                    .monospacedDigit()
                    .font(emphasized ? .headline : .caption)
            }
            .font(.caption)

            if showsProgress {
                ProgressView(value: value ?? 0, total: 100)
                    .tint(tint)
                    // AppKit reuses this native control across appearance changes
                    // and can reset its tint. Recreate it so SwiftUI reapplies tint.
                    .id(colorScheme)
                    .opacity(value == nil ? 0.25 : 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
