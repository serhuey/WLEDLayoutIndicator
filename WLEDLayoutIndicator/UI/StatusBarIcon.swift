import SwiftUI
import AppKit

/// Menu-bar label: a 5×3 grid of dots tinted with the current layout colour,
/// or a warning triangle when the WLED link has failed.
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

    /// 5 × 3 dot grid rendered to a non-template NSImage.
    private var dotGridImage: NSImage {
        let c = coordinator.currentColor
        let color = NSColor(
            red: CGFloat(c.r) / 255.0,
            green: CGFloat(c.g) / 255.0,
            blue: CGFloat(c.b) / 255.0,
            alpha: 1.0
        )
        let dot: CGFloat = 3
        let gap: CGFloat = 2
        let w = CGFloat(5) * dot + CGFloat(4) * gap   // 23
        let h = CGFloat(3) * dot + CGFloat(2) * gap   // 13

        let image = NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
            for row in 0..<3 {
                for col in 0..<5 {
                    let x = CGFloat(col) * (dot + gap)
                    let y = CGFloat(row) * (dot + gap)
                    let rect = NSRect(x: x, y: y, width: dot, height: dot)
                    let path = NSBezierPath(roundedRect: rect, xRadius: 0.5, yRadius: 0.5)
                    color.setFill()
                    path.fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
