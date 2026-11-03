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
            MenuBarBalanceView(title: service.menuBarTitle,
                               toppedUpPercent: service.selectedBalance?.toppedUpPercent,
                               grantedPercent: service.selectedBalance?.grantedPercent,
                               isStale: service.isStale, style: settings.menuBarStyle)
        }
        .menuBarExtraStyle(.window)

        Window("DSHMeter", id: "settings") {
            SettingsView(service: service, settings: settings)
                .appAppearance(settings.appearance)
        }
        .defaultSize(width: 840, height: 700)
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
