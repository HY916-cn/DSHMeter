import AppKit
import SwiftUI

@main
struct DSHMeterApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var service: BalanceService

    init() {
        let settings = AppSettings()
        let service = BalanceService(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _service = StateObject(wrappedValue: service)
        Task { @MainActor in service.refresh() }
    }

    var body: some Scene {
        MenuBarExtra {
            BalancePopover(service: service, settings: settings)
                .appAppearance(settings.appearance)
        } label: {
            HStack(spacing: 4) {
                if settings.menuBarStyle != .balanceOnly {
                    Image(systemName: service.isStale ? "clock.badge.exclamationmark" : "creditcard")
                }
                if settings.menuBarStyle != .iconOnly {
                    Text(service.menuBarTitle).monospacedDigit()
                }
            }
            .accessibilityLabel("DSHMeter · " + service.menuBarTitle
                                + (service.isStale ? " · " + L10n.string("data.stale") : ""))
        }
        .menuBarExtraStyle(.window)

        Window("DSHMeter", id: "settings") {
            SettingsView(service: service, settings: settings)
                .appAppearance(settings.appearance)
        }
        .defaultSize(width: 720, height: 580)
        .windowResizability(.contentMinSize)
    }
}

extension View {
    func appAppearance(_ appearance: AppAppearance) -> some View {
        preferredColorScheme(appearance.colorScheme)
            .background(WindowAppearanceSynchronizer(appearance: appearance))
    }
}

private struct WindowAppearanceSynchronizer: NSViewRepresentable {
    let appearance: AppAppearance
    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }
    func updateNSView(_ nsView: AppearanceView, context: Context) {
        nsView.appearanceMode = appearance
        nsView.apply()
    }
    final class AppearanceView: NSView {
        var appearanceMode = AppAppearance.system
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() {
            switch appearanceMode {
            case .system: window?.appearance = nil
            case .light: window?.appearance = NSAppearance(named: .aqua)
            case .dark: window?.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
}
