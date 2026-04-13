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
    @Published public private(set) var status: LinkStatus = .idle

    public let settings: SettingsStore
    private let monitor: LayoutMonitor
    private let client: WLEDClient
    private var monitorTask: Task<Void, Never>?
    private var configObserver: AnyCancellable?
    private var sleepObservers: [NSObjectProtocol] = []
    /// When true, we override brightness to `dimBrightness` instead of config value.
    private var isDimmed = false
    private static let dimBrightness = 2
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "coordinator")

    public init(
        settings: SettingsStore,
        monitor: LayoutMonitor,
        client: WLEDClient
    ) {
        self.settings = settings
        self.monitor = monitor
        self.client = client
    }

    public func start() {
        monitor.start()

        // Consume layout changes.
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await sourceID in self.monitor.updates {
                await self.handleLayoutChange(sourceID: sourceID)
            }
        }

        // React to config edits: re-send the current colour (which may be
        // different now after an edit to the mapping or brightness).
        // Debounce 0.15 s so dragging the brightness slider doesn't flood WLED.
        configObserver = settings.$config
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
        configObserver = nil
        for o in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            DistributedNotificationCenter.default().removeObserver(o)
        }
        sleepObservers = []
        monitor.stop()
    }

    /// Fire a manual test from Settings. Bypasses debounce so the user always
    /// sees an immediate attempt.
    public func testConnection() async -> Result<Void, Error> {
        let wled = settings.config.wled
        let entry = ColorMapper.entry(for: currentSourceID, config: settings.config)
        do {
            try await client.sendOnce(entry, wled: wled)
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
        await client.setEntry(entry, wled: wled)
    }

    // MARK: - Layout

    private func handleLayoutChange(sourceID: String) async {
        currentSourceID = sourceID
        let config = settings.config
        let entry = ColorMapper.entry(for: sourceID, config: config)
        currentColor = entry.color
        logger.info("layout=\(sourceID, privacy: .public) -> rgb=\(entry.color.r),\(entry.color.g),\(entry.color.b)")

        var wled = config.wled
        if isDimmed {
            wled.brightness = Self.dimBrightness
        }
        await client.setEntry(entry, wled: wled)
        status = .ok(lastSent: entry.color)
    }
}
