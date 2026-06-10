import XCTest
@testable import WLEDLayoutIndicator

@MainActor
final class SettingsStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WLEDSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func test_firstLaunch_createsDefaultConfig() throws {
        let fakeIDs = ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: fakeIDs)

        XCTAssertEqual(store.config.mapping.count, 2)
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.US"]?.color,
                       RGB(r: 0, g: 120, b: 255))
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.Russian"]?.color,
                       RGB(r: 255, g: 40, b: 40))
        // Default pattern is solid
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.US"]?.pattern, .solid)

        let file = tmpDir.appendingPathComponent("config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_firstLaunch_unknownLayout_getsGrey() throws {
        let fakeIDs = ["com.apple.keylayout.Klingon"]
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: fakeIDs)
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.Klingon"]?.color,
                       RGB(r: 80, g: 80, b: 80))
    }

    func test_update_persistsAndRoundTrips() throws {
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: [])
        var customPattern = Pattern.blank
        customPattern[1, 1] = true
        store.update {
            $0.wled.host = "192.168.1.100"
            $0.wled.brightness = 64
            $0.mapping["com.apple.keylayout.Dvorak"] = LayoutEntry(
                color: RGB(r: 10, g: 20, b: 30),
                pattern: customPattern
            )
        }

        let reloaded = SettingsStore(directory: tmpDir, systemSourceIDs: [])
        XCTAssertEqual(reloaded.config.wled.host, "192.168.1.100")
        XCTAssertEqual(reloaded.config.wled.brightness, 64)
        let entry = reloaded.config.mapping["com.apple.keylayout.Dvorak"]
        XCTAssertEqual(entry?.color, RGB(r: 10, g: 20, b: 30))
        XCTAssertEqual(entry?.pattern, customPattern)
    }

    func test_update_noChange_doesNothing() {
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: [])
        let before = store.config
        store.update { _ in /* no mutation */ }
        XCTAssertEqual(store.config, before)
    }

    // MARK: - v1 migration

    func test_loadV1Config_migratesToCurrentSchema() throws {
        // Pre-pattern format: mapping was [String: RGB], "defaultColor"
        // instead of "defaultEntry", no rotation / per-app fields.
        let v1JSON = """
        {
          "wled": { "host": "192.168.1.42", "brightness": 200, "segmentId": 1, "ledCount": 25 },
          "mapping": {
            "com.apple.keylayout.US": { "r": 0, "g": 120, "b": 255 },
            "com.apple.keylayout.Russian": { "r": 255, "g": 40, "b": 40 }
          },
          "defaultColor": { "r": 80, "g": 80, "b": 80 },
          "launchAtLogin": true
        }
        """
        let file = tmpDir.appendingPathComponent("config.json")
        try Data(v1JSON.utf8).write(to: file)

        let store = SettingsStore(directory: tmpDir, systemSourceIDs: [])
        let config = store.config

        XCTAssertEqual(config.wled.host, "192.168.1.42")
        XCTAssertEqual(config.wled.brightness, 200)
        XCTAssertEqual(config.wled.segmentId, 1)
        XCTAssertEqual(config.mapping["com.apple.keylayout.US"],
                       LayoutEntry(color: RGB(r: 0, g: 120, b: 255), pattern: .solid))
        XCTAssertEqual(config.mapping["com.apple.keylayout.Russian"]?.color,
                       RGB(r: 255, g: 40, b: 40))
        XCTAssertEqual(config.defaultEntry, LayoutEntry(color: RGB(r: 80, g: 80, b: 80)))
        XCTAssertTrue(config.launchAtLogin)
        // New fields fall back to defaults.
        XCTAssertEqual(config.matrixRotation, 0)
        XCTAssertFalse(config.autoSwitchOnAppFocus)
        XCTAssertTrue(config.appLayoutMemory.isEmpty)
    }

    func test_corruptConfig_fallsBackToFirstLaunchDefaults() throws {
        let file = tmpDir.appendingPathComponent("config.json")
        try Data("not json at all".utf8).write(to: file)

        let store = SettingsStore(directory: tmpDir,
                                  systemSourceIDs: ["com.apple.keylayout.US"])
        XCTAssertEqual(store.config.mapping.count, 1)
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.US"]?.color,
                       RGB(r: 0, g: 120, b: 255))
    }
}
