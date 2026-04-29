import Foundation

/// Hard-coded preset colours offered in the settings UI. Ordered by hue
/// (warm → cool → pink → white) into a 4×4 grid. The seven presets that
/// `Config.buildMapping(for:)` auto-assigns by language family are
/// preserved at their natural hue positions.
enum ColorPalette {
    static let presets: [RGB] = [
        // Row 1 — warm
        RGB(r: 255, g: 40,  b: 40),   // red          (RU/UK/BY)
        RGB(r: 255, g: 140, b: 0),    // orange       (Spanish)
        RGB(r: 255, g: 200, b: 0),    // yellow       (German)
        RGB(r: 255, g: 240, b: 100),  // gold
        // Row 2 — green/cyan
        RGB(r: 170, g: 255, b: 40),   // lime
        RGB(r: 40,  g: 200, b: 80),   // green
        RGB(r: 0,   g: 180, b: 140),  // teal
        RGB(r: 0,   g: 200, b: 200),  // cyan         (French)
        // Row 3 — blue/purple
        RGB(r: 0,   g: 180, b: 255),  // sky
        RGB(r: 0,   g: 120, b: 255),  // blue         (English)
        RGB(r: 90,  g: 70,  b: 255),  // indigo
        RGB(r: 170, g: 70,  b: 255),  // purple
        // Row 4 — pink/white
        RGB(r: 220, g: 0,   b: 200),  // magenta
        RGB(r: 255, g: 60,  b: 180),  // pink
        RGB(r: 255, g: 220, b: 180),  // warm white
        RGB(r: 255, g: 255, b: 255),  // white
    ]
}
