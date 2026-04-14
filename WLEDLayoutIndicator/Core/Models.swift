import Foundation

/// Domain models for WLEDLayoutIndicator.
///
/// All three types are marked `nonisolated` so they opt out of the module's
/// default actor isolation (Xcode 26 / Swift 6.3 may default to `@MainActor`
/// per SE-0466). These are plain value types — we want them usable from any
/// context, including the `WLEDClient` actor, without forcing `await` hops.

// MARK: - RGB

public nonisolated struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Integer array form expected by WLED JSON API: `[R, G, B]`.
    public var jsonArray: [Int] { [Int(r), Int(g), Int(b)] }
}

// MARK: - Pattern

/// 5×5 pixel bitmap. `true` = LED on (in the layout's colour), `false` = off.
/// Stored as a flat 25-element array in row-major order (row 0 = top).
public nonisolated struct Pattern: Codable, Equatable, Hashable, Sendable {
    /// 25 bools, row-major. Index = row * 5 + col.
    public var pixels: [Bool]

    public init(pixels: [Bool]) {
        precondition(pixels.count == 25)
        self.pixels = pixels
    }

    /// All LEDs on (solid fill — legacy behaviour).
    public static let solid = Pattern(pixels: Array(repeating: true, count: 25))

    /// All LEDs off.
    public static let blank = Pattern(pixels: Array(repeating: false, count: 25))

    public subscript(row: Int, col: Int) -> Bool {
        get { pixels[row * 5 + col] }
        set { pixels[row * 5 + col] = newValue }
    }

    /// Returns a new pattern rotated clockwise by `degrees` (0 / 90 / 180 / 270).
    public func rotated(by degrees: Int) -> Pattern {
        let steps = ((degrees % 360 + 360) % 360) / 90
        var result = self
        for _ in 0..<steps {
            result = result.rotated90CW()
        }
        return result
    }

    /// Single 90° clockwise rotation: new[row][col] = old[4-col][row].
    private func rotated90CW() -> Pattern {
        var result = Pattern.blank
        for row in 0..<5 {
            for col in 0..<5 {
                result[row, col] = self[4 - col, row]
            }
        }
        return result
    }
}

// MARK: - LayoutEntry

/// Per-layout configuration: colour + which LEDs are lit.
public nonisolated struct LayoutEntry: Codable, Equatable, Hashable, Sendable {
    public var color: RGB
    public var pattern: Pattern

    public init(color: RGB, pattern: Pattern = .solid) {
        self.color = color
        self.pattern = pattern
    }
}

// MARK: - Config

/// Full, user-editable configuration. Persisted as JSON.
public nonisolated struct Config: Codable, Equatable, Sendable {

    public nonisolated struct WLED: Codable, Equatable, Sendable {
        /// IP address or mDNS name, e.g. "192.168.1.42" or "atom.local".
        /// Scheme/port are not stored — always `http://<host>/json/state`.
        public var host: String
        /// 0...255
        public var brightness: Int
        /// WLED segment id. Atom Matrix has a single default segment = 0.
        public var segmentId: Int
        /// Number of LEDs in the segment. 25 for Atom Matrix 5x5.
        public var ledCount: Int

        public init(host: String, brightness: Int, segmentId: Int, ledCount: Int) {
            self.host = host
            self.brightness = brightness
            self.segmentId = segmentId
            self.ledCount = ledCount
        }
    }

    public var wled: WLED
    /// Keyed by Carbon `kTISPropertyInputSourceID`, e.g. "com.apple.keylayout.Russian".
    public var mapping: [String: LayoutEntry]
    /// Fallback for source IDs not present in `mapping`.
    public var defaultEntry: LayoutEntry
    /// Launch app at login (persisted only — application of this setting
    /// is the responsibility of `SMAppService` at runtime).
    public var launchAtLogin: Bool
    /// Physical rotation of the matrix in degrees (0 / 90 / 180 / 270).
    /// Applied to every pattern before sending — does not alter stored patterns.
    public var matrixRotation: Int

    public init(wled: WLED, mapping: [String: LayoutEntry], defaultEntry: LayoutEntry,
                launchAtLogin: Bool, matrixRotation: Int = 0) {
        self.wled = wled
        self.mapping = mapping
        self.defaultEntry = defaultEntry
        self.launchAtLogin = launchAtLogin
        self.matrixRotation = matrixRotation
    }

    /// Defaults used on first launch (or when the config file is missing/corrupt).
    /// The mapping starts empty — `SettingsStore` auto-populates it from the
    /// system's enabled layouts via `Config.buildMapping(for:)`.
    public static let initial = Config(
        wled: .init(host: "", brightness: 128, segmentId: 0, ledCount: 25),
        mapping: [:],
        defaultEntry: LayoutEntry(color: RGB(r: 80, g: 80, b: 80)),
        launchAtLogin: false,
        matrixRotation: 0
    )

    /// Builds a mapping from an array of installed source IDs by matching
    /// each ID against known language patterns.
    public static func buildMapping(for sourceIDs: [String]) -> [String: LayoutEntry] {
        var result: [String: LayoutEntry] = [:]
        for id in sourceIDs {
            result[id] = LayoutEntry(color: knownColor(for: id))
        }
        return result
    }

    /// Returns a preset colour for well-known keyboard layouts, or a neutral
    /// grey for anything unrecognised.
    public static func knownColor(for sourceID: String) -> RGB {
        let lower = sourceID.lowercased()

        // Russian / Ukrainian / Belarusian — red
        if lower.contains("russian") || lower.contains("ukrainian")
            || lower.contains("belarusian") {
            return RGB(r: 255, g: 40, b: 40)
        }
        // English variants — blue
        if lower.hasSuffix(".us") || lower.hasSuffix(".abc")
            || lower.contains("british") || lower.contains("australian")
            || lower.contains("canadian") || lower.contains("usdvorak")
            || lower.contains("uscolemak") || lower.contains("usinternational") {
            return RGB(r: 0, g: 120, b: 255)
        }
        // German — yellow
        if lower.contains("german") {
            return RGB(r: 255, g: 200, b: 0)
        }
        // French — cyan
        if lower.contains("french") {
            return RGB(r: 0, g: 200, b: 200)
        }
        // Spanish — orange
        if lower.contains("spanish") {
            return RGB(r: 255, g: 140, b: 0)
        }
        // Unrecognised — grey
        return RGB(r: 80, g: 80, b: 80)
    }
}

// MARK: - Status

/// Last-known state of the WLED link, surfaced in the menu bar.
public nonisolated enum LinkStatus: Equatable, Sendable {
    case idle
    case ok(lastSent: RGB)
    case failed(message: String)
}
