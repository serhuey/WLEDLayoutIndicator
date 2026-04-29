import SwiftUI
import AppKit

/// Menu-bar label: a 5×5 grid mirroring the original (un-rotated) WLED
/// pattern — "on" pixels tinted with the current layout colour, drawn
/// over a dark rounded background so the icon stays legible on any menu
/// bar appearance. Shows a warning triangle when the link has failed.
///
/// MenuBarExtra with `.menu` style renders the label as a template image,
/// stripping all colour. Rendering to `NSImage` with `isTemplate = false`
/// bypasses this so the tint is preserved.
struct StatusBarIcon: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.status {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        default:
            Image(nsImage: dotGridImage)
        }
    }

    /// 5 × 5 pattern-masked grid on a dark rounded background.
    /// Padding 1 pt + dot 2 pt + gap 1 pt → 16 × 16 pt icon.
    private var dotGridImage: NSImage {
        let c = coordinator.currentColor
        let color = NSColor(
            red: CGFloat(c.r) / 255.0,
            green: CGFloat(c.g) / 255.0,
            blue: CGFloat(c.b) / 255.0,
            alpha: 1.0
        )
        let pattern = coordinator.currentPattern
        let dot: CGFloat = 2
        let gap: CGFloat = 1
        let pad: CGFloat = 1
        let grid = CGFloat(5) * dot + CGFloat(4) * gap   // 14
        let side = grid + 2 * pad                         // 16

        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let bgRect = NSRect(x: 0, y: 0, width: side, height: side)
            NSColor.black.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()

            // Off-pixels: dim tint of the layout colour so the grid stays
            // visible even when the pattern is empty (.blank).
            let offColor = color.withAlphaComponent(0.18)
            for row in 0..<5 {
                for col in 0..<5 {
                    let x = pad + CGFloat(col) * (dot + gap)
                    let y = pad + CGFloat(row) * (dot + gap)
                    let rect = NSRect(x: x, y: y, width: dot, height: dot)
                    let path = NSBezierPath(roundedRect: rect, xRadius: 0.3, yRadius: 0.3)
                    if pattern[row, col] {
                        color.setFill()
                    } else {
                        offColor.setFill()
                    }
                    path.fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
