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

    /// 5 columns × 3 rows of small dots — visually echoes the Atom Matrix.
    private var dotGrid: some View {
        let c = coordinator.currentColor
        let color = Color(
            red:   Double(c.r) / 255.0,
            green: Double(c.g) / 255.0,
            blue:  Double(c.b) / 255.0
        )
        return VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(color)
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
    }
}
