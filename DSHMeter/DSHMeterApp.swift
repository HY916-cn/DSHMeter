import AppKit
import DSHMeterCore
import SwiftUI

@main
struct DSHMeterApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var usageService: BalanceService

    init() {
        let settings = AppSettings()
        let usageService = BalanceService(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _usageService = StateObject(wrappedValue: usageService)
        Task { @MainActor in usageService.refresh() }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(service: usageService, settings: settings)
                .appAppearance(settings.appearanceMode)
        } label: {
            MenuBarProgressView(
                remainingPercent: menuBarSnapshot.remainingPercent,
                remainingTimePercent: menuBarSnapshot.remainingTimePercent,
                title: menuBarSnapshot.title,
                style: effectiveStyle,
                attentionLevel: menuBarSnapshot.attentionLevel,
                isStale: menuBarSnapshot.isStale,
                appearance: menuBarAppearance,
                flashContext: settings.developerPreviewEnabled ? nil : usageService.source?.rawValue
            )
            .accessibilityLabel("DSHMeter · " + menuBarSnapshot.title)
        }
        .menuBarExtraStyle(.window)

        Window("DSHMeter", id: CodexMeterWindowID.settings) {
            AppSettingsView(service: usageService, settings: settings)
                .appAppearance(settings.appearanceMode)
        }
        .defaultSize(width: 840, height: 700)
        .windowResizability(.contentMinSize)

        Window("DSHMeter", id: CodexMeterWindowID.about) {
            AboutView(settings: settings)
                .appAppearance(settings.appearanceMode)
        }
        .defaultSize(width: 500, height: 620)
        .windowResizability(.contentSize)
    }

    private var menuBarWindow: BalanceInfo? {
        settings.popoverContent.selectedMenuBarWindow(from: usageService.windows)
    }

    private var effectiveStyle: MenuBarDisplayStyle {
        settings.developerPreviewEnabled ? settings.menuBarStyle
            : settings.balanceDisplayStyle(for: menuBarWindow?.currency.rawValue ?? settings.preferredCurrency)
    }

    private var menuBarAppearance: MenuBarAppearance {
        settings.developerAppearance
    }

    private var menuBarSnapshot: MenuBarPreviewSnapshot {
        if settings.developerPreviewEnabled {
            let preview = settings.developerPreviewSnapshot
            return MenuBarPreviewSnapshot(remainingPercent: preview.remainingPercent,
                remainingTimePercent: preview.remainingTimePercent,
                title: L10n.menuMoney(Decimal(preview.remainingPercent ?? 0), currency: settings.preferredCurrency),
                attentionLevel: preview.attentionLevel, isStale: preview.isStale)
        }
        let window = menuBarWindow
        let reference = window.flatMap { settings.referenceBalance(for: $0.currency.rawValue) }
        let percent = window.flatMap { balance in reference.map {
            max(0, min(100, NSDecimalNumber(decimal: balance.totalBalance / $0 * 100).doubleValue))
        } }
        return MenuBarPreviewSnapshot(
            remainingPercent: percent.map { Int($0.rounded()) },
            remainingTimePercent: nil,
            title: window.map { L10n.menuMoney($0.totalBalance, currency: $0.currency.rawValue) }
                ?? (usageService.isLoading ? "…" : "—"),
            attentionLevel: window.map { $0.totalBalance > 0 ? .normal : .critical } ?? .normal,
            isStale: usageService.isStale
        )
    }
}

private extension View {
    /// Synchronizes both SwiftUI content and the AppKit host window. The latter
    /// is required for MenuBarExtra materials to change appearance immediately.
    func appAppearance(_ mode: AppAppearanceMode) -> some View {
        preferredColorScheme(mode.preferredColorScheme)
            .background(WindowAppearanceSynchronizer(mode: mode))
    }
}

private struct WindowAppearanceSynchronizer: NSViewRepresentable {
    let mode: AppAppearanceMode

    func makeNSView(context: Context) -> AppearanceTrackingView {
        AppearanceTrackingView(mode: mode)
    }

    func updateNSView(_ nsView: AppearanceTrackingView, context: Context) {
        nsView.apply(mode: mode)
    }

    final class AppearanceTrackingView: NSView {
        private var mode: AppAppearanceMode

        init(mode: AppAppearanceMode) {
            self.mode = mode
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWindowAppearance()
        }

        func apply(mode: AppAppearanceMode) {
            self.mode = mode
            applyWindowAppearance()
        }

        private func applyWindowAppearance() {
            window?.appearance = mode.windowAppearance
        }
    }
}
