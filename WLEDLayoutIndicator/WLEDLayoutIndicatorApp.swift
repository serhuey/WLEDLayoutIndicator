import SwiftUI
import AppKit
import os

@main
struct WLEDLayoutIndicatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(delegate.coordinator)
                .environmentObject(delegate.settings)
        } label: {
            StatusBarIcon(coordinator: delegate.coordinator)
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
            client: WLEDClient(),
            focusMonitor: AppFocusMonitor()
        )
        super.init()
    }

    private var windowObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()

        // Agent apps (LSUIElement) can't reliably activate to the foreground.
        // Combine: `.floating` keeps window above other apps, NSApp.activate +
        // makeKeyAndOrderFront grabs focus. Hook both didBecomeKey AND
        // didBecomeMain — with SettingsLink the window may become main before
        // becoming key, and hooking only didBecomeKey misses that case.
        let log = Logger(subsystem: "com.wledlayout.indicator", category: "window")
        let hook: (Notification) -> Void = { notification in
            guard let window = notification.object as? NSWindow,
                  window.canBecomeKey else { return }
            MainActor.assumeIsolated {
                log.info("\(notification.name.rawValue, privacy: .public) on \(window.title, privacy: .public)")
                window.level = .floating
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        let center = NotificationCenter.default
        windowObserver = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main, using: hook)
        _ = center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil, queue: .main, using: hook)
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

        // Activate the app BEFORE opening Settings — SettingsLink/openSettings
        // on its own won't bring an LSUIElement agent app to the foreground,
        // so the window opens unfocused on first click.
        if #available(macOS 14.0, *) {
            SettingsMenuButton()
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

@available(macOS 14.0, *)
private struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
