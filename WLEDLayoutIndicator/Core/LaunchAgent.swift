import Foundation
import ServiceManagement

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

    /// One-shot migration from the v1 Login Item (`SMAppService.mainApp`) to
    /// the LaunchAgent. Runs at most once per install; preserves the user's
    /// previous "Launch at login" preference.
    static func migrateLoginItemIfNeeded() {
        let key = "didMigrateLoginItemToAgent.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let mainApp = SMAppService.mainApp
        let wasEnabled = (mainApp.status == .enabled)

        try? mainApp.unregister()
        if wasEnabled {
            try? service.register()
        }
    }
}
