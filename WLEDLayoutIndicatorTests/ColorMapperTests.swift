import XCTest
@testable import WLEDLayoutIndicator

final class ColorMapperTests: XCTestCase {

    private let config = Config.initial

    func test_mapsKnownSourceID() {
        let c = ColorMapper.color(for: "com.apple.keylayout.Russian", config: config)
        XCTAssertEqual(c, RGB(r: 255, g: 40, b: 40))
    }

    func test_mapsSecondKnownSourceID() {
        let c = ColorMapper.color(for: "com.apple.keylayout.US", config: config)
        XCTAssertEqual(c, RGB(r: 0, g: 120, b: 255))
    }

    func test_unknownSourceID_fallsBackToDefault() {
        let c = ColorMapper.color(for: "com.apple.keylayout.Klingon", config: config)
        XCTAssertEqual(c, config.defaultColor)
    }

    func test_caseSensitive() {
        // TIS IDs are case-sensitive reverse-DNS strings; a lower-cased
        // lookup must not match.
        let c = ColorMapper.color(for: "com.apple.keylayout.russian", config: config)
        XCTAssertEqual(c, config.defaultColor)
    }
}
