import Foundation

/// Pure `(sourceID, Config) -> RGB` mapping. Testable in isolation.
public enum ColorMapper {
    /// Returns the colour for the given input source ID, falling back to
    /// `config.defaultColor` if no explicit entry exists.
    public static func color(for sourceID: String, config: Config) -> RGB {
        config.mapping[sourceID] ?? config.defaultColor
    }
}
