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

        // SettingsLink is the Apple-blessed way on macOS 14+. Below that we
        // fall back to the AppKit selector; the deprecation warning at
        // runtime is the reason we prefer SettingsLink when available.
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle:            return "Status: idle"
        case .ok(let rgb):     return "Status: OK  (\(rgb.r), \(rgb.g), \(rgb.b))"
        case .failed(let msg): return "Status: ⚠︎ \(msg)"
        }
    }
}
