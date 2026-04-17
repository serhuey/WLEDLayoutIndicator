import SwiftUI

/// Menu-bar label: a 5×3 grid of dots tinted with the current layout colour,
/// or a warning triangle when the WLED link has failed.
///
/// SF Symbols in MenuBarExtra labels are rendered as template images by macOS
/// and ignore `.foregroundStyle` tinting. Using explicit SwiftUI shapes
/// (RoundedRectangle) bypasses template rendering so the colour is preserved.
struct StatusBarIcon: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.status {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        default:
            dotGrid
        }
    }

    /// 5 × 3 dot grid drawn via Canvas — fixed 23 × 13 pt frame.
    /// Canvas with an explicit frame is the only reliable way to draw
    /// custom-coloured content in a MenuBarExtra label; VStack/HStack
    /// with ForEach collapses to zero size in that context.
    private var dotGrid: some View {
        let c = coordinator.currentColor
        let color = Color(
            red:   Double(c.r) / 255.0,
            green: Double(c.g) / 255.0,
            blue:  Double(c.b) / 255.0
        )
        let dot: CGFloat = 3
        let gap: CGFloat = 2
        return Canvas { ctx, _ in
            for row in 0..<3 {
                for col in 0..<5 {
                    let x = CGFloat(col) * (dot + gap)
                    let y = CGFloat(row) * (dot + gap)
                    let rect = CGRect(x: x, y: y, width: dot, height: dot)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                             with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(5) * dot + CGFloat(4) * gap,   // 23
               height: CGFloat(3) * dot + CGFloat(2) * gap)  // 13
    }
}
