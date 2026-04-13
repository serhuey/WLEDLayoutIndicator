import XCTest
@testable import WLEDLayoutIndicator

final class ColorMapperTests: XCTestCase {

    private func configWith(mapping: [String: LayoutEntry]) -> Config {
        Config(
            wled: .init(host: "", brightness: 128, segmentId: 0, ledCount: 25),
            mapping: mapping,
            defaultEntry: LayoutEntry(color: RGB(r: 80, g: 80, b: 80)),
            launchAtLogin: false
        )
    }

    func test_mapsKnownSourceID() {
        let entry = LayoutEntry(color: RGB(r: 255, g: 40, b: 40))
        let config = configWith(mapping: ["com.apple.keylayout.Russian": entry])
        let result = ColorMapper.entry(for: "com.apple.keylayout.Russian", config: config)
        XCTAssertEqual(result, entry)
    }

    func test_unknownSourceID_fallsBackToDefault() {
        let config = configWith(mapping: [:])
        let result = ColorMapper.entry(for: "com.apple.keylayout.Klingon", config: config)
        XCTAssertEqual(result, config.defaultEntry)
    }

    func test_caseSensitive() {
        let entry = LayoutEntry(color: RGB(r: 255, g: 40, b: 40))
        let config = configWith(mapping: ["com.apple.keylayout.Russian": entry])
        let result = ColorMapper.entry(for: "com.apple.keylayout.russian", config: config)
        XCTAssertEqual(result, config.defaultEntry)
    }

    func test_patternIsPreserved() {
        var customPattern = Pattern.blank
        customPattern[0, 0] = true
        customPattern[4, 4] = true
        let entry = LayoutEntry(color: RGB(r: 0, g: 120, b: 255), pattern: customPattern)
        let config = configWith(mapping: ["com.apple.keylayout.US": entry])
        let result = ColorMapper.entry(for: "com.apple.keylayout.US", config: config)
        XCTAssertEqual(result.pattern, customPattern)
        XCTAssertTrue(result.pattern[0, 0])
        XCTAssertFalse(result.pattern[2, 2])
    }
}
