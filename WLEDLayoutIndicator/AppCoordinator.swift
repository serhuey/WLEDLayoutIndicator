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
        configObserver = settings.$config
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.handleLayoutChange(sourceID: self.currentSourceID) }
            }
    }

    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        configObserver = nil
        monitor.stop()
    }

    /// Fire a manual test from Settings. Bypasses debounce so the user always
    /// sees an immediate attempt.
    public func testConnection() async -> Result<Void, Error> {
        let wled = settings.config.wled
        let probe = ColorMapper.color(for: currentSourceID, config: settings.config)
        do {
            try await client.sendOnce(probe, wled: wled)
            status = .ok(lastSent: probe)
            return .success(())
        } catch {
            status = .failed(message: String(describing: error))
            return .failure(error)
        }
    }

    // MARK: -

    private func handleLayoutChange(sourceID: String) async {
        currentSourceID = sourceID
        let config = settings.config
        let color = ColorMapper.color(for: sourceID, config: config)
        currentColor = color
        logger.info("layout=\(sourceID, privacy: .public) -> rgb=\(color.r),\(color.g),\(color.b)")

        await client.setColor(color, wled: config.wled)
        // The actor silently eats errors, so we optimistically mark OK.
        // A future improvement: have WLEDClient publish a status stream.
        status = .ok(lastSent: color)
    }
}
