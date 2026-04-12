import Foundation
import Combine
import os

/// Loads and saves `Config` as JSON in `Application Support/WLEDLayoutIndicator/config.json`.
///
/// Publishes the current config so UI and coordinator react to edits.
/// This object is `@MainActor` because it is observed by SwiftUI.
@MainActor
public final class SettingsStore: ObservableObject {

    @Published public private(set) var config: Config

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.wledlayout.indicator", category: "settings")

    /// - Parameters:
    ///   - directory: override for tests. Production uses Application Support.
    ///   - systemSourceIDs: override for tests. `nil` = read from Carbon TIS at runtime.
    public init(directory: URL? = nil, systemSourceIDs: [String]? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("config.json")

        // Ensure directory exists. Failure here is non-fatal — we fall back to
        // in-memory defaults for the session.
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )

        if let loaded = Self.loadFromDisk(url: fileURL) {
            self.config = loaded
            logger.info("Loaded config from disk (\(loaded.mapping.count) layouts)")
        } else {
            // First launch: detect installed keyboard layouts and pre-populate
            // the mapping with known colours.
            let ids = systemSourceIDs ?? LayoutMonitor.enabledKeyboardSourceIDs()
            logger.info("First launch — detected \(ids.count) keyboard layouts: \(ids.joined(separator: ", "), privacy: .public)")
            var initial = Config.initial
            initial.mapping = Config.buildMapping(for: ids)
            self.config = initial
            try? Self.writeToDisk(url: fileURL, config: initial)
        }
    }

    public func update(_ transform: (inout Config) -> Void) {
        var next = config
        transform(&next)
        guard next != config else { return }
        config = next
        do {
            try Self.writeToDisk(url: fileURL, config: next)
        } catch {
            logger.error("Failed to write config: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Static helpers (also used by tests)

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("WLEDLayoutIndicator", isDirectory: true)
    }

    static func loadFromDisk(url: URL) -> Config? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    static func writeToDisk(url: URL, config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
    }
}
