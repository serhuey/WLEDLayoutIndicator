import XCTest
@testable import WLEDLayoutIndicator

// `Pattern` alone is ambiguous in the test target (collides with a system
// type), so resolve it to the app module's type once here.
private typealias Pattern = WLEDLayoutIndicator.Pattern

final class PatternTests: XCTestCase {

    /// Asymmetric pattern: single pixel at top-left corner.
    private var corner: Pattern {
        var p = Pattern.blank
        p[0, 0] = true
        return p
    }

    func test_rotate0_isIdentity() {
        XCTAssertEqual(corner.rotated(by: 0), corner)
    }

    func test_rotate90_movesTopLeftToTopRight() {
        let rotated = corner.rotated(by: 90)
        XCTAssertFalse(rotated[0, 0])
        XCTAssertTrue(rotated[0, 4])
    }

    func test_rotate180_movesTopLeftToBottomRight() {
        let rotated = corner.rotated(by: 180)
        XCTAssertTrue(rotated[4, 4])
    }

    func test_rotate270_movesTopLeftToBottomLeft() {
        let rotated = corner.rotated(by: 270)
        XCTAssertTrue(rotated[4, 0])
    }

    func test_rotate360_isIdentity() {
        var pattern = Pattern.blank
        pattern[1, 2] = true
        pattern[3, 0] = true
        XCTAssertEqual(pattern.rotated(by: 360), pattern)
    }

    func test_negativeDegrees_normalizeToPositive() {
        // -90° == 270°
        XCTAssertEqual(corner.rotated(by: -90), corner.rotated(by: 270))
    }

    func test_fourQuarterTurns_composeToIdentity() {
        var pattern = Pattern.blank
        pattern[0, 1] = true
        pattern[2, 3] = true
        pattern[4, 4] = true
        let roundTrip = pattern
            .rotated(by: 90).rotated(by: 90).rotated(by: 90).rotated(by: 90)
        XCTAssertEqual(roundTrip, pattern)
    }

    func test_solidAndBlank_areRotationInvariant() {
        for degrees in [90, 180, 270] {
            XCTAssertEqual(Pattern.solid.rotated(by: degrees), .solid)
            XCTAssertEqual(Pattern.blank.rotated(by: degrees), .blank)
        }
    }

    func test_rotate90_middleRowBecomesMiddleColumn() {
        var rowPattern = Pattern.blank
        for col in 0..<5 { rowPattern[2, col] = true }
        var expected = Pattern.blank
        for row in 0..<5 { expected[row, 2] = true }
        XCTAssertEqual(rowPattern.rotated(by: 90), expected)
    }
}
