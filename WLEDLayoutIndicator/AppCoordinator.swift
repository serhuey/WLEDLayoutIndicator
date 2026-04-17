import Foundation
import Combine
import SwiftUI
import os

/// Wires the layout monitor, color mapper, WLED client and settings store
/// together. Publishes the most recent source ID, resolved colour and link
/// status for the UI layer to display.
@MainActor
public final class AppCoordinator: ObservableObject {

    @Published public private(set) var currentSourceID: String = "—"
    @Published public private(set) var currentColor: RGB = .init(r: 0, g: 0, b: 0)
    @Published public private(set) var currentPattern: Pattern = .solid
    @Published public private(set) var status: LinkStatus = .idle
    @Published public private(set) var currentBundleID: String?

    public let settings: SettingsStore
    private let monitor: LayoutMonitor
    private let focusMonitor: AppFocusMonitor
    private let client: WLEDClient
    private var monitorTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var configObserver: AnyCancellable?
    private var sleepObservers: [NSObjectProtocol] = []
    /// When true, we override brightness to `dimBrightness` instead of config value.
    private var isDimmed = false
    private static let dimBrightness = 2
    /// After we assert a layout on focus, ignore layout changes that aren't
    /// what we set — Chrome/Electron/Telegram fight back immediately.
    /// Without this, the app's override would overwrite our memory with its
    /// preferred layout, poisoning the stored value.
    private var assertedLayoutForApp: String?
    private var assertedSourceID: String?
    private var assertedUntil: Date?
    private static let assertWindow: TimeInterval = 1.2
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "coordinator")

    public init(
        settings: SettingsStore,
        monitor: LayoutMonitor,
        client: WLEDClient,
        focusMonitor: AppFocusMonitor
    ) {
        self.settings = settings
        self.monitor = monitor
        self.client = client
        self.focusMonitor = focusMonitor
    }

    public func start() {
        monitor.start()
        focusMonitor.start()

        // Consume layout changes.
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await sourceID in self.monitor.updates {
                await self.handleLayoutChange(sourceID: sourceID)
            }
        }

        // Consume focus changes (per-app layout memory).
        focusTask = Task { [weak self] in
            guard let self else { return }
            for await bundleID in self.focusMonitor.updates {
                await self.handleAppFocus(bundleID: bundleID)
            }
        }

        // React to config edits: re-send the current colour (which may be
        // different now after an edit to the mapping or brightness).
        // Debounce 0.15 s so dragging the brightness slider doesn't flood WLED.
        // Skip re-send when only the per-app memory or toggle changed —
        // those don't affect what's on the matrix.
        configObserver = settings.$config
            .map(Self.wledRelevantSnapshot)
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.handleLayoutChange(sourceID: self.currentSourceID) }
            }

        // If no host is configured yet, auto-discover on the network.
        if settings.config.wled.host.isEmpty {
            autoDiscoverHost()
        }

        // Dim on sleep / screensaver, restore on wake.
        subscribeSleepWake()
    }

    /// The subset of Config that, when changed, requires a re-send to WLED.
    /// Excludes per-app memory and the auto-switch toggle.
    private struct WLEDRelevant: Equatable {
        let wled: Config.WLED
        let mapping: [String: LayoutEntry]
        let defaultEntry: LayoutEntry
        let matrixRotation: Int
    }
    private static func wledRelevantSnapshot(_ c: Config) -> WLEDRelevant {
        WLEDRelevant(wled: c.wled, mapping: c.mapping,
                     defaultEntry: c.defaultEntry, matrixRotation: c.matrixRotation)
    }

    /// Runs mDNS discovery once and picks the first matching device.
    private func autoDiscoverHost() {
        let discovery = WLEDDiscovery()
        discovery.start()

        // Observe results for up to 5 seconds (discovery auto-stops).
        var observer: AnyCancellable?
        observer = discovery.$devices
            .filter { !$0.isEmpty }
            .first()
            .sink { [weak self] devices in
                guard let self, let first = devices.first else { return }
                self.logger.info("Auto-discovered WLED: \(first.hostname, privacy: .public)")
                self.settings.update { $0.wled.host = first.hostname }
                observer?.cancel()
            }
        // The AnyCancellable is retained by the closure via `observer` until
        // it fires or discovery times out and gets deallocated.
    }

    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        focusTask?.cancel()
        focusTask = nil
        configObserver = nil
        for o in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            DistributedNotificationCenter.default().removeObserver(o)
        }
        sleepObservers = []
        monitor.stop()
        focusMonitor.stop()
    }

    /// Fire a manual test from Settings. Bypasses debounce so the user always
    /// sees an immediate attempt.
    public func testConnection() async -> Result<Void, Error> {
        let wled = settings.config.wled
        let entry = ColorMapper.entry(for: currentSourceID, config: settings.config)
        do {
            try await client.sendOnce(rotated(entry), wled: wled)
            status = .ok(lastSent: entry.color)
            return .success(())
        } catch {
            status = .failed(message: String(describing: error))
            return .failure(error)
        }
    }

    // MARK: - Sleep / Wake

    private func subscribeSleepWake() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()

        // Dim: system sleep or screensaver activation
        let dimEvents: [(center: Any, name: NSNotification.Name)] = [
            (ws, NSWorkspace.willSleepNotification),
            (ws, NSWorkspace.screensDidSleepNotification),
            (dc, NSNotification.Name("com.apple.screensaver.didstart")),
        ]
        for event in dimEvents {
            let center = event.center
            let o: NSObjectProtocol
            if let wsc = center as? NotificationCenter {
                o = wsc.addObserver(forName: event.name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleDim() }
                }
            } else {
                o = dc.addObserver(forName: event.name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleDim() }
                }
            }
            sleepObservers.append(o)
        }

        // Restore: system wake or screensaver stop
        let wakeEvents: [(center: Any, name: NSNotification.Name)] = [
            (ws, NSWorkspace.didWakeNotification),
            (ws, NSWorkspace.screensDidWakeNotification),
            (dc, NSNotification.Name("com.apple.screensaver.didstop")),
        ]
        for event in wakeEvents {
            let center = event.center
            let o: NSObjectProtocol
            if let wsc = center as? NotificationCenter {
                o = wsc.addObserver(forName: event.name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleRestore() }
                }
            } else {
                o = dc.addObserver(forName: event.name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handleRestore() }
                }
            }
            sleepObservers.append(o)
        }
    }

    private func handleDim() {
        guard !isDimmed else { return }
        isDimmed = true
        logger.info("Dimming WLED (sleep/screensaver)")
        Task { await sendCurrentEntry() }
    }

    private func handleRestore() {
        guard isDimmed else { return }
        isDimmed = false
        logger.info("Restoring WLED brightness (wake/screensaver stop)")
        Task { await sendCurrentEntry() }
    }

    /// Sends the current entry with effective brightness (dimmed or config).
    private func sendCurrentEntry() async {
        var wled = settings.config.wled
        if isDimmed {
            wled.brightness = Self.dimBrightness
        }
        let entry = ColorMapper.entry(for: currentSourceID, config: settings.config)
        await client.setEntry(rotated(entry), wled: wled)
    }

    /// Applies the configured matrix rotation to a layout entry's pattern.
    private func rotated(_ entry: LayoutEntry) -> LayoutEntry {
        let degrees = settings.config.matrixRotation
        guard degrees != 0 else { return entry }
        return LayoutEntry(color: entry.color, pattern: entry.pattern.rotated(by: degrees))
    }

    // MARK: - Layout

    private func handleLayoutChange(sourceID: String) async {
        currentSourceID = sourceID
        let config = settings.config
        let entry = ColorMapper.entry(for: sourceID, config: config)
        let rotatedEntry = rotated(entry)
        currentColor = entry.color
        currentPattern = entry.pattern
        logger.info("layout=\(sourceID, privacy: .public) -> rgb=\(entry.color.r),\(entry.color.g),\(entry.color.b)")

        // Per-app memory: record this layout for the active foreground app.
        recordLayoutForCurrentApp(sourceID: sourceID)

        var wled = config.wled
        if isDimmed {
            wled.brightness = Self.dimBrightness
        }
        await client.setEntry(rotatedEntry, wled: wled)
        status = .ok(lastSent: entry.color)
    }

    // MARK: - Per-app focus / memory

    private func handleAppFocus(bundleID: String?) async {
        // Always update currentBundleID (informational), but skip the rest
        // for nil / our own bundle / disabled toggle.
        currentBundleID = bundleID
        guard settings.config.autoSwitchOnAppFocus,
              let bundleID,
              bundleID != Bundle.main.bundleIdentifier else {
            return
        }
        guard let saved = settings.config.appLayoutMemory[bundleID],
              saved != currentSourceID else {
            return
        }
        // Verify the saved source still exists; if not, drop the stale entry.
        guard LayoutMonitor.enabledKeyboardSourceIDs().contains(saved) else {
            logger.warning("Dropping stale memory entry for \(bundleID, privacy: .public): \(saved, privacy: .public) no longer enabled")
            settings.update { $0.appLayoutMemory.removeValue(forKey: bundleID) }
            return
        }

        // Chrome/Electron/Telegram set their preferred layout on activation,
        // racing with us. Wait for that to settle, then apply ours — and
        // re-apply once more in case the app reacts to our switch.
        try? await Task.sleep(for: .milliseconds(250))
        guard currentBundleID == bundleID else { return }

        logger.info("Focus -> \(bundleID, privacy: .public): restoring \(saved, privacy: .public)")
        assertedLayoutForApp = bundleID
        assertedSourceID = saved
        assertedUntil = Date().addingTimeInterval(Self.assertWindow)
        LayoutMonitor.selectInputSource(id: saved)

        // Second assertion after the app's post-activation handling would
        // typically fire. If user has meanwhile switched layout manually,
        // currentSourceID will already equal `saved` and the early-out in
        // selectInputSource short-circuits via the layout-change handler.
        try? await Task.sleep(for: .milliseconds(400))
        guard currentBundleID == bundleID,
              currentSourceID != saved else { return }
        logger.info("Re-asserting \(saved, privacy: .public) for \(bundleID, privacy: .public) (app fought back)")
        LayoutMonitor.selectInputSource(id: saved)
    }

    private func recordLayoutForCurrentApp(sourceID: String) {
        guard settings.config.autoSwitchOnAppFocus,
              let bundleID = currentBundleID,
              bundleID != Bundle.main.bundleIdentifier else {
            return
        }
        // Within the assert window, an incoming layout change that differs
        // from what we just set is the app overriding us — do NOT record it,
        // or memory gets poisoned with the app's preferred layout.
        if let until = assertedUntil, until > Date(),
           assertedLayoutForApp == bundleID,
           let asserted = assertedSourceID,
           sourceID != asserted {
            logger.debug("Ignoring override \(sourceID, privacy: .public) for \(bundleID, privacy: .public) (within assert window)")
            return
        }
        guard settings.config.appLayoutMemory[bundleID] != sourceID else { return }
        settings.update { $0.appLayoutMemory[bundleID] = sourceID }
    }
}
