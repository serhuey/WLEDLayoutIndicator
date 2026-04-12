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
        // Pass explicit source IDs so we don't depend on the test runner's
        // actual installed keyboards.
        let fakeIDs = ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: fakeIDs)

        // Mapping should contain exactly the IDs we passed.
        XCTAssertEqual(store.config.mapping.count, 2)
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.US"],
                       RGB(r: 0, g: 120, b: 255))
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.Russian"],
                       RGB(r: 255, g: 40, b: 40))

        // File should exist on disk after first launch.
        let file = tmpDir.appendingPathComponent("config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_firstLaunch_unknownLayout_getsGrey() throws {
        let fakeIDs = ["com.apple.keylayout.Klingon"]
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: fakeIDs)
        XCTAssertEqual(store.config.mapping["com.apple.keylayout.Klingon"],
                       RGB(r: 80, g: 80, b: 80))
    }

    func test_update_persistsAndRoundTrips() throws {
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: [])
        store.update {
            $0.wled.host = "192.168.1.100"
            $0.wled.brightness = 64
            $0.mapping["com.apple.keylayout.Dvorak"] = RGB(r: 10, g: 20, b: 30)
        }

        // New store reads same directory → should load the edited values.
        let reloaded = SettingsStore(directory: tmpDir, systemSourceIDs: [])
        XCTAssertEqual(reloaded.config.wled.host, "192.168.1.100")
        XCTAssertEqual(reloaded.config.wled.brightness, 64)
        XCTAssertEqual(
            reloaded.config.mapping["com.apple.keylayout.Dvorak"],
            RGB(r: 10, g: 20, b: 30)
        )
    }

    func test_update_noChange_doesNothing() {
        let store = SettingsStore(directory: tmpDir, systemSourceIDs: [])
        let before = store.config
        store.update { _ in /* no mutation */ }
        XCTAssertEqual(store.config, before)
    }
}
