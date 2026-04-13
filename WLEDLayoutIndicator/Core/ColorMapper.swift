import Foundation

/// Pure `(sourceID, Config) -> LayoutEntry` mapping. Testable in isolation.
public enum ColorMapper {
    /// Returns the layout entry (colour + pattern) for the given input source ID,
    /// falling back to `config.defaultEntry` if no explicit entry exists.
    public static func entry(for sourceID: String, config: Config) -> LayoutEntry {
        config.mapping[sourceID] ?? config.defaultEntry
    }
}
