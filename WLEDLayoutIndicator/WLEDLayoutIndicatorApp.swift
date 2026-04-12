import SwiftUI
import AppKit

@main
struct WLEDLayoutIndicatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(delegate.coordinator)
                .environmentObject(delegate.settings)
        } label: {
            StatusBarIcon()
                .environmentObject(delegate.coordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(delegate.coordinator)
                .environmentObject(delegate.settings)
                .frame(width: 520, height: 560)
        }
    }
}

/// AppKit delegate. Owns the object graph so we can start/stop cleanly
/// at the correct lifecycle points.
///
/// Marked `@MainActor` so its `init` runs on the main actor and can safely
/// construct main-actor-isolated types (`SettingsStore`, `LayoutMonitor`,
/// `AppCoordinator`). `NSApplicationDelegateAdaptor` guarantees the delegate
/// is instantiated on the main thread at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let settings: SettingsStore
    let coordinator: AppCoordinator

    override init() {
        let store = SettingsStore()
        self.settings = store
        self.coordinator = AppCoordinator(
            settings: store,
            monitor: LayoutMonitor(),
            client: WLEDClient()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}

/// Menu items rendered inside `MenuBarExtra`.
struct MenuBarContent: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Text("Layout: \(coordinator.currentSourceID)")
        Text(statusText).foregroundStyle(.secondary)
        Divider()

        Button("Settings…") {
            Self.openAndActivateSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    /// Opens the Settings scene and forces the app to the foreground.
    /// `SettingsLink` doesn't reliably activate the app (menu-bar-only apps
    /// have no activation policy), so we do it manually.
    private static func openAndActivateSettings() {
        // Temporarily switch to regular activation policy so the window
        // can come to front, then switch back after a short delay.
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        // Bring the settings window to front explicitly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where window.title.contains("Settings") || window.title.contains("Preferences") {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            // Go back to accessory (no Dock icon) once the window is up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle:            return "Status: idle"
        case .ok(let rgb):     return "Status: OK  (\(rgb.r), \(rgb.g), \(rgb.b))"
        case .failed(let msg): return "Status: ⚠︎ \(msg)"
        }
    }
}
