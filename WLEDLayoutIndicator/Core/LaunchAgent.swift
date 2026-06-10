import Foundation
import ServiceManagement
import os

/// LaunchAgent registration for resilient menu-bar presence.
///
/// macOS can silently kill agent apps under memory pressure (jetsam) or when
/// the responsiveness checker decides the process is unresponsive — even with
/// `disableSuddenTermination()`. Registering the same binary as a LaunchAgent
/// with `KeepAlive = { Crashed = true; SuccessfulExit = false; }` makes
/// launchd respawn the process after involuntary termination, while still
/// allowing a clean `Cmd-Q` to actually quit.
///
/// The plist ships at `Contents/Library/LaunchAgents/` inside the app bundle
/// and is registered through `SMAppService.agent`, which is sandbox-friendly
/// on macOS 13+.
enum LaunchAgent {
    static let plistName = "serhuey.WLEDLayoutIndicator.agent.plist"

    static let service = SMAppService.agent(plistName: plistName)

    private static let logger = Logger(subsystem: "com.wledlayout.indicator", category: "launchagent")

    /// One-shot migration from the v1 Login Item (`SMAppService.mainApp`) to
    /// the LaunchAgent. Preserves the user's previous "Launch at login"
    /// preference. The done-flag is only set once the agent is actually
    /// registered (or there was nothing to migrate) — if registration fails,
    /// e.g. pending user approval, we retry on the next launch instead of
    /// silently dropping the preference.
    static func migrateLoginItemIfNeeded() {
        let key = "didMigrateLoginItemToAgent.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let mainApp = SMAppService.mainApp
        let wasEnabled = (mainApp.status == .enabled)

        do {
            try mainApp.unregister()
        } catch {
            // Usually "not registered" — harmless either way; the agent
            // registration below is what actually matters.
            logger.info("Login item unregister: \(error.localizedDescription, privacy: .public)")
        }

        guard wasEnabled else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        do {
            try service.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            logger.error("LaunchAgent registration failed, will retry next launch: \(error.localizedDescription, privacy: .public)")
        }
    }
}
